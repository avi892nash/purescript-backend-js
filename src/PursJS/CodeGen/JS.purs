-- | Ports `Language.PureScript.CodeGen.JS` (purescript@c4a35b3,
-- | src/Language/PureScript/CodeGen/JS.hs). Transforms `CoreFn.Module Ann`
-- | into `CoreImp.Module`.
-- |
-- | Mapping (PursJS <-> CodeGen/JS.hs line):
-- |   runModuleToJs / moduleToJs        JS.hs:52-82  (`moduleToJs`)
-- |   annotatePure / maybePure          JS.hs:89-125
-- |   pureIife / pureApp                JS.hs:127-131
-- |   renameImports / freshModuleName   JS.hs:140-157
-- |   importToJs                        JS.hs:161-164
-- |   exportsToJs                       JS.hs:168-169
-- |   reExportsToJs                     JS.hs:173-174
-- |   moduleImportPath                  JS.hs:176-177
-- |   walkModule / walkAST              JS.hs:182-187 (`replaceModuleAccessors`)
-- |   runtimeLazy                       JS.hs:209-229 (not yet ported — Effect module diff)
-- |   moduleBindToJs / bindToJs         JS.hs:232-247
-- |   nonRecToJS                        JS.hs:253-261
-- |   guessEffects                      JS.hs:263-267
-- |   withPos                           JS.hs:269-274 (we always return js unchanged — no source maps yet)
-- |   valueToJs / valueToJs'            JS.hs:282-354
-- |   iife                              JS.hs:356-357
-- |   literalToValueJS                  JS.hs:359-366
-- |   extendObj                         JS.hs:369-386
-- |   varToJs / qualifiedToJS           JS.hs:390-399
-- |   foreignIdent                      JS.hs:401-402
-- |   bindersToJs                       JS.hs:406-444
-- |   binderToJs / binderToJs'          JS.hs:446-481
-- |   literalToBinderJS                 JS.hs:483-513
-- |   accessorString                    JS.hs:515-516
-- |   FFINamespace ("$foreign")         JS.hs:518-519
module PursJS.CodeGen.JS where

import Prelude

import Control.Monad.State (evalState)
import Data.Array (cons, fold, length, range, snoc, zip, zipWith, (!!), (..), (:))
import Data.Array as Array
import Data.Either (Either(..))
import Data.Foldable (foldM, foldr, foldl)
import Data.List (List)
import Data.List as List
import Data.List.NonEmpty (NonEmptyList)
import Data.List.NonEmpty as NEL
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Set (Set)
import Data.Set as Set
import Data.String as Str
import Data.String.CodeUnits as SC
import Data.Traversable (traverse, sequence)
import Data.Tuple (Tuple(..), fst, snd)
import PursJS.CodeGen.Common (anyNameToJs, identCharToText, identToJs, moduleNameToJs, properToJs)
import PursJS.CodeGen.Laziness (hasEagerSiblingRef, lazyName, rewriteSiblingRefs, runtimeLazyAST)
import PursJS.CodeGen.Supply (Supply, freshName)
import PursJS.CoreImp.Optimizer (optimize)
import PursJS.CoreImp.Traversals (everything) as Trav
import Data.Set as Set
import PursJS.Comments (Comment)
import PursJS.CoreFn.Types (Bind(..), Binder(..), CaseAlternative(..), ConstructorType(..), Expr(..), Literal(..), Meta(..)) as CF
import PursJS.CoreFn.Types (Ann, Bind, Binder, CaseAlternative, Expr, Literal, Module)
import PursJS.CoreImp.AST (AST(..), BinaryOperator(..), CIComments(..), InitializerEffects(..), UnaryOperator(..))
import PursJS.CoreImp.Module (Export(..), Import(..), Module) as M
import PursJS.Names (Ident(..), ModuleName(..), Qualified(..), QualifiedBy(..), ProperName, SourcePos(..), SourceSpan(..), runIdent, runModuleName, runProperName)
import PursJS.PSString (PSString, mkString)

-- | Foreign module namespace identifier
ffiNamespace :: String
ffiNamespace = "$foreign"

-- | True iff `ast` contains any `Var "$runtime_lazy"` reference. Used to
-- | decide whether to prepend the `$runtime_lazy` runtime helper to the module.
usesRuntimeLazy :: AST -> Boolean
usesRuntimeLazy = Trav.everything (||) check
  where
  check (Var _ "$runtime_lazy") = true
  check _ = false

-- | Hard-coded primitive module list (mirrors Constants.Prim.primModules in
-- | the Haskell compiler).
primModules :: Array ModuleName
primModules =
  [ ModuleName "Prim"
  , ModuleName "Prim.Boolean"
  , ModuleName "Prim.Coerce"
  , ModuleName "Prim.Ordering"
  , ModuleName "Prim.Row"
  , ModuleName "Prim.RowList"
  , ModuleName "Prim.Symbol"
  , ModuleName "Prim.Int"
  , ModuleName "Prim.TypeError"
  ]

m_Prim :: ModuleName
m_Prim = ModuleName "Prim"

-- | Run the supply monad on `moduleToJs` and return a CoreImp.Module.
runModuleToJs :: { noComments :: Boolean } -> Module Ann -> Maybe PSString -> M.Module
runModuleToJs opts m foreignInclude =
  evalState (moduleToJs opts m foreignInclude) 0

moduleToJs
  :: { noComments :: Boolean }
  -> Module Ann
  -> Maybe PSString
  -> Supply M.Module
moduleToJs opts m foreignInclude = do
  let mn = m.name
  let coms = m.comments
  let imps = m.imports
  let exps = m.exports
  let reExps = m.reExports
  let foreigns = m.foreign_
  let decls = m.decls

  -- usedNames: all the names introduced at the top level
  let usedNames = Array.concatMap getNames decls

  -- imps': unique module names from imports
  let importedMods = ordNub (map snd imps)

  -- mnLookup: ModuleName -> JS-safe alias, avoiding collisions
  let mnLookup = renameImports usedNames importedMods mn

  -- Generate code for each declaration
  jsDeclLists <- traverse (moduleBindToJs opts mn) decls
  -- If any binding referenced `$runtime_lazy`, prepend its definition.
  -- Mirrors `if needRuntimeLazy then [runtimeLazy] : jsDecls else jsDecls`
  -- at JS.hs:64.
  let needsRuntimeLazy = Array.any (Array.any usesRuntimeLazy) jsDeclLists
      jsDeclLists' = if needsRuntimeLazy
                       then Array.cons [runtimeLazyAST] jsDeclLists
                       else jsDeclLists
  -- Run AST-level optimizer passes
  optimized <- optimize (map identToJs exps) jsDeclLists'
  let jsDecls = Array.concat optimized
  let annotated = map annotatePure jsDecls

  -- header
  let header = if opts.noComments then [] else coms

  -- foreign import (only if foreigns is non-empty and we have an include path)
  let foreign' = case foreignInclude of
        Just inc | not (Array.null foreigns) -> [ M.Import ffiNamespace inc ]
        _ -> []

  -- Replace ModuleAccessor with Indexer, tracking which module names are used.
  let walked = walkModule mnLookup annotated
  let usedModuleNames = Set.union (Map.keys reExps # Set.fromFoldable) walked.usedModules
  let renamedBody = walked.body

  -- jsImports: filter imports to only used modules, skipping mn itself and prim modules
  let filteredImports =
        Array.filter (\im -> Set.member im usedModuleNames)
          (Array.filter (\im -> im /= mn && not (Array.elem im primModules)) importedMods)
  let jsImports = map (importToJs mnLookup) filteredImports

  let foreignExps = Array.intersect exps foreigns
  let standardExps = arrayDifference exps foreignExps
  let reExpsList = Array.filter
        (\(Tuple k _) -> not (Array.elem k primModules))
        (Map.toUnfoldable reExps :: Array (Tuple ModuleName (Array Ident)))

  let jsExports =
        catMaybes
          [ exportsToJs foreignInclude foreignExps
          , exportsToJs Nothing standardExps
          ] <>
        Array.mapMaybe reExportsToJs reExpsList

  pure
    { header
    , imports: foreign' <> jsImports
    , body: renamedBody
    , exports: jsExports
    }
  where
  getNames :: Bind Ann -> Array Ident
  getNames (CF.NonRec _ id _) = [id]
  getNames (CF.Rec vs) = map _.ident vs

importToJs :: Map ModuleName String -> ModuleName -> M.Import
importToJs lookup mn' =
  let alias = fromMaybe (moduleNameToJs mn') (Map.lookup mn' lookup)
  in M.Import alias (moduleImportPath mn')

moduleImportPath :: ModuleName -> PSString
moduleImportPath mn = mkString ("../" <> runModuleName mn <> "/index.js")

exportsToJs :: Maybe PSString -> Array Ident -> Maybe M.Export
exportsToJs from is =
  case NEL.fromFoldable (map runIdent is) of
    Just nel -> Just (M.Export nel from)
    Nothing -> Nothing

reExportsToJs :: Tuple ModuleName (Array Ident) -> Maybe M.Export
reExportsToJs (Tuple mn is) = exportsToJs (Just (moduleImportPath mn)) is

renameImports
  :: Array Ident
  -> Array ModuleName
  -> ModuleName
  -> Map ModuleName String
renameImports used mods selfMn = go Map.empty used mods
  where
  go acc usedAcc = case _ of
    [] -> acc
    arr ->
      case Array.uncons arr of
        Nothing -> acc
        Just { head: mn', tail } ->
          let mnj = moduleNameToJs mn'
          in if mn' /= selfMn && Array.elem (Ident mnj) usedAcc
             then
               let newName = freshModuleName 1 mnj usedAcc
               in go (Map.insert mn' newName acc) (Array.cons (Ident newName) usedAcc) tail
             else
               go (Map.insert mn' mnj acc) usedAcc tail

  freshModuleName :: Int -> String -> Array Ident -> String
  freshModuleName i mn' usedAcc =
    let newName = mn' <> "_" <> show i
    in if Array.elem (Ident newName) usedAcc
       then freshModuleName (i + 1) mn' usedAcc
       else newName

-- ===== module bind =====

moduleBindToJs
  :: { noComments :: Boolean }
  -> ModuleName
  -> Bind Ann
  -> Supply (Array AST)
moduleBindToJs opts mn = bindToJs
  where
  bindToJs :: Bind Ann -> Supply (Array AST)
  bindToJs (CF.NonRec ann ident val)
    | isTypeClassConstructor ann = pure []
  bindToJs (CF.NonRec ann ident val) = do
    js <- nonRecToJS ann ident val
    pure [js]
  bindToJs (CF.Rec vs) = do
    -- Materialise each binding into a CoreImp.AST first so we can inspect it.
    initAsts <- traverse (\v -> do
        ast <- nonRecToJS v.ann v.ident v.expr
        pure { ident: v.ident, ast }) vs
    let siblingNames = Set.fromFoldable (map (\v -> identToJs v.ident) vs)
    -- A binding is in `wrapSet` if its initializer eagerly references any
    -- sibling (i.e. a `Var sibling` not inside a `Function`). These are the
    -- ones we lazy-wrap with `$runtime_lazy`.
    let wrapSet = Set.fromFoldable $ Array.mapMaybe (\b -> case b.ast of
          VariableIntroduction _ name (Just (Tuple _ initExpr))
            | hasEagerSiblingRef siblingNames initExpr -> Just name
          _ -> Nothing) initAsts
    if Set.isEmpty wrapSet
      then pure (map _.ast initAsts)
      else do
        let nonWrapped = Array.filter (\b -> not (Set.member (astName b.ast) wrapSet)) initAsts
            wrapped = Array.filter (\b -> Set.member (astName b.ast) wrapSet) initAsts
            -- Inside non-wrapped binding bodies, references to *wrapped*
            -- siblings need to go through `$lazy_X(0)` because the wrapped
            -- bindings won't exist yet at any point where a closure body might
            -- be entered before module-init completes.
            nonWrappedAsts = map (\b -> rewriteSiblingsExpr wrapSet b.ast) nonWrapped
            -- Inside wrapped binding init bodies, the same rule applies — refs
            -- to OTHER wrapped siblings need to be `$lazy_Y(0)`.
            lazyDecls = map (mkLazyDecl wrapSet mn) wrapped
            materials = map mkMaterial wrapped
        pure (nonWrappedAsts <> lazyDecls <> materials)
    where
    astName :: AST -> String
    astName (VariableIntroduction _ n _) = n
    astName _ = ""

    -- Rewrite sibling refs to wrapped siblings as `$lazy_X(0)` calls,
    -- preserving the surrounding VariableIntroduction.
    rewriteSiblingsExpr :: Set.Set String -> AST -> AST
    rewriteSiblingsExpr wrapSet (VariableIntroduction ss n (Just (Tuple eff e))) =
      VariableIntroduction ss n (Just (Tuple eff (rewriteSiblingRefs wrapSet e)))
    rewriteSiblingsExpr _ other = other

    mkLazyDecl :: Set.Set String -> ModuleName -> _ -> AST
    mkLazyDecl wrapSet modName b = case b.ast of
      VariableIntroduction ss name (Just (Tuple eff initExpr)) ->
        VariableIntroduction ss (lazyName name)
          (Just (Tuple eff
            (App Nothing (Var Nothing "$runtime_lazy")
              [ StringLiteral Nothing (mkString (runIdent b.ident))
              , StringLiteral Nothing (mkString (runModuleName modName))
              , Function Nothing Nothing []
                  (Block Nothing [Return Nothing (rewriteSiblingRefs wrapSet initExpr)])
              ])))
      other -> other

    mkMaterial :: _ -> AST
    mkMaterial b = case b.ast of
      VariableIntroduction _ name (Just (Tuple eff _)) ->
        VariableIntroduction Nothing name
          (Just (Tuple eff
            (App Nothing (Var Nothing (lazyName name))
              [NumericLiteral Nothing (Left 0)])))
      other -> other

  isTypeClassConstructor :: Ann -> Boolean
  isTypeClassConstructor a = case a.meta of
    Just CF.IsTypeClassConstructor -> true
    _ -> false

  nonRecToJS :: Ann -> Ident -> Expr Ann -> Supply AST
  nonRecToJS ann ident val =
    let coms = ann.comments
    in if not (Array.null coms) && not opts.noComments
       then do
         inner <- nonRecToJSStripped ann ident val
         pure (Comment (SourceComments coms) inner)
       else nonRecToJSStripped ann ident val

  nonRecToJSStripped :: Ann -> Ident -> Expr Ann -> Supply AST
  nonRecToJSStripped _ ident val = do
    js <- valueToJs val
    pure (VariableIntroduction Nothing (identToJs ident) (Just (Tuple (guessEffects val) js)))

  -- | JS.hs:263-267 — `guessEffects`.
  -- | Local-let-bound names (BySourcePos) and synthesised applications are
  -- | known-side-effect-free; everything else conservatively `UnknownEffects`.
  guessEffects :: Expr Ann -> InitializerEffects
  guessEffects (CF.Var _ (Qualified (BySourcePos _) _)) = NoEffects
  guessEffects (CF.App ann _ _) = case ann.meta of
    Just CF.IsSyntheticApp -> NoEffects
    _ -> UnknownEffects
  guessEffects _ = UnknownEffects

  -- ===== values =====

  -- | JS.hs:282-285 — `valueToJs`. The Haskell version also wraps the result
  -- | in `withPos ss` so source maps work; we omit that since we don't emit
  -- | source maps.
  valueToJs :: Expr Ann -> Supply AST
  valueToJs e = valueToJs' e

  -- | JS.hs:287-354 — `valueToJs'`. One equation per CoreFn `Expr` variant.
  valueToJs' :: Expr Ann -> Supply AST
  -- JS.hs:288-289 — Literal: defer to literalToValueJS
  valueToJs' (CF.Literal ann l) = literalToValueJS l
  -- JS.hs:290-293 — Var with IsConstructor meta: dot into `.value` (nullary)
  -- or `.create` (n-ary). Constructors are emitted as objects with these fields.
  valueToJs' (CF.Var ann name) = case ann.meta of
    Just (CF.IsConstructor _ []) ->
      pure (accessorString (mkString "value") (qualifiedToJS identity name))
    Just (CF.IsConstructor _ _) ->
      pure (accessorString (mkString "create") (qualifiedToJS identity name))
    -- JS.hs:322-327 — IsForeign: local foreigns become `$foreign.<name>`,
    -- cross-module foreigns go through the usual qualifiedToJS path.
    Just CF.IsForeign -> case name of
      Qualified (ByModuleName mn') ident
        | mn' == mn -> pure (foreignIdent ident)
        | otherwise -> pure (varToJs name)
      _ -> pure (varToJs name)  -- silently no-op fallback
    _ -> pure (varToJs name)
  -- JS.hs:294-295 — Accessor: simple property index.
  valueToJs' (CF.Accessor _ prop val) = do
    v <- valueToJs val
    pure (accessorString prop v)
  -- JS.hs:296-302 — ObjectUpdate: with a known copy-list we lower to a single
  -- ObjectLiteral; otherwise we fall back to a runtime for..in copy via extendObj.
  valueToJs' (CF.ObjectUpdate _ o copy ps) = do
    obj <- valueToJs o
    sts <- traverse (\(Tuple k v) -> Tuple k <$> valueToJs v) ps
    case copy of
      Nothing -> extendObj obj sts
      Just names ->
        pure (ObjectLiteral Nothing
                ((map (\n -> Tuple n (accessorString n obj)) names) <> sts))
  -- JS.hs:303-308 — Abs: function (arg) { return body; }. UnusedIdent emits
  -- a zero-arg function so we don't generate a `var $__unused` parameter.
  valueToJs' (CF.Abs _ arg val) = do
    ret <- valueToJs val
    let args = case arg of
                 UnusedIdent -> []
                 _ -> [identToJs arg]
    pure (Function Nothing Nothing args (Block Nothing [Return Nothing ret]))
  -- JS.hs:309-321 — App: curried function application. We collect the
  -- arg-spine with unApp, then either lower a fully-saturated constructor to
  -- `new C(args)`, drop a newtype constructor application to its sole arg, or
  -- emit a chain of `App fn [arg]` calls otherwise.
  valueToJs' eApp@(CF.App _ _ _) = do
    let { f, args } = unApp eApp []
    args' <- traverse valueToJs args
    case f of
      CF.Var ann name -> case ann.meta of
        Just CF.IsNewtype -> case Array.head args' of
          Just a -> pure a
          Nothing -> pure (Var Nothing "<<newtype constructor without arg>>")
        Just (CF.IsConstructor _ fields) | Array.length args == Array.length fields ->
          pure (Unary Nothing New (App Nothing (qualifiedToJS identity name) args'))
        _ -> do
          fJs <- valueToJs f
          pure (foldl curryApp fJs args')
      _ -> do
        fJs <- valueToJs f
        pure (foldl curryApp fJs args')
  -- JS.hs:329-331 — Case: defer to bindersToJs with the scrutinees.
  valueToJs' (CF.Case ann values binders) = do
    vals <- traverse valueToJs values
    bindersToJs ann.ss binders vals
  -- JS.hs:332-335 — Let: emit an IIFE with the bindings followed by a return.
  valueToJs' (CF.Let _ ds val) = do
    declsArr <- Array.concat <$> traverse bindToJs ds
    ret <- valueToJs val
    pure (App Nothing
            (Function Nothing Nothing [] (Block Nothing (declsArr <> [Return Nothing ret])))
            [])
  -- JS.hs:336-344 — Constructor with no fields: emit an IIFE that builds a
  -- single-instance object. Newtype constructors take the IsNewtype short-cut:
  -- `var T = { create: function (value) { return value; } }`.
  valueToJs' (CF.Constructor ann _ ctor []) = case ann.meta of
    Just CF.IsNewtype ->
      pure (VariableIntroduction Nothing (properToJs ctor) (Just (Tuple UnknownEffects
              (ObjectLiteral Nothing
                [ Tuple (mkString "create")
                    (Function Nothing Nothing ["value"]
                      (Block Nothing [Return Nothing (Var Nothing "value")]))
                ]))))
    _ ->
      pure (iife (properToJs ctor)
              [ Function Nothing (Just (properToJs ctor)) [] (Block Nothing [])
              , Assignment Nothing
                  (accessorString (mkString "value") (Var Nothing (properToJs ctor)))
                  (Unary Nothing New (App Nothing (Var Nothing (properToJs ctor)) []))
              ])
  valueToJs' (CF.Constructor _ _ ctor fields) =
    let ctorBody =
          map (\f -> Assignment Nothing
                       (accessorString (mkString (identToJs f)) (Var Nothing "this"))
                       (var f))
              fields
        constructor =
          Function Nothing (Just (properToJs ctor))
                   (map identToJs fields)
                   (Block Nothing ctorBody)
        body =
          Unary Nothing New
            (App Nothing (Var Nothing (properToJs ctor))
              (map var fields))
        createFn =
          foldr
            (\f inner ->
              Function Nothing Nothing [identToJs f]
                (Block Nothing [Return Nothing inner]))
            body
            fields
    in pure (iife (properToJs ctor)
              [ constructor
              , Assignment Nothing
                  (accessorString (mkString "create") (Var Nothing (properToJs ctor)))
                  createFn
              ])

  iife :: String -> Array AST -> AST
  iife v exprs =
    App Nothing
      (Function Nothing Nothing []
        (Block Nothing (exprs <> [Return Nothing (Var Nothing v)])))
      []

  var :: Ident -> AST
  var = Var Nothing <<< identToJs

  literalToValueJS :: Literal (Expr Ann) -> Supply AST
  literalToValueJS (CF.NumericLiteralInt i) = pure (NumericLiteral Nothing (Left i))
  literalToValueJS (CF.NumericLiteralNumber n) = pure (NumericLiteral Nothing (Right n))
  literalToValueJS (CF.StringLiteral s) = pure (StringLiteral Nothing s)
  literalToValueJS (CF.CharLiteral c) = pure (StringLiteral Nothing (mkString (Str.singleton (Str.codePointFromChar c))))
  literalToValueJS (CF.BooleanLiteral b) = pure (BooleanLiteral Nothing b)
  literalToValueJS (CF.ArrayLiteral xs) = ArrayLiteral Nothing <$> traverse valueToJs xs
  literalToValueJS (CF.ObjectLiteral ps) = do
    qs <- traverse (\(Tuple k v) -> Tuple k <$> valueToJs v) ps
    pure (ObjectLiteral Nothing qs)

  extendObj :: AST -> Array (Tuple PSString AST) -> Supply AST
  extendObj obj sts = do
    newObj <- freshName
    keyN <- freshName
    evObj <- freshName
    let jsKey = Var Nothing keyN
        jsNewObj = Var Nothing newObj
        jsEvaluatedObj = Var Nothing evObj
        evaluate = VariableIntroduction Nothing evObj (Just (Tuple UnknownEffects obj))
        objAssign = VariableIntroduction Nothing newObj (Just (Tuple NoEffects (ObjectLiteral Nothing [])))
        cond = App Nothing
                 (accessorString (mkString "call")
                   (accessorString (mkString "hasOwnProperty") (ObjectLiteral Nothing [])))
                 [jsEvaluatedObj, jsKey]
        assign = Block Nothing
                   [ Assignment Nothing
                       (Indexer Nothing jsKey jsNewObj)
                       (Indexer Nothing jsKey jsEvaluatedObj)
                   ]
        copy = ForIn Nothing keyN jsEvaluatedObj (Block Nothing [IfElse Nothing cond assign Nothing])
        extend = map (\(Tuple s j) -> Assignment Nothing (accessorString s jsNewObj) j) sts
        block = Block Nothing
                  ([evaluate, objAssign, copy] <> extend <> [Return Nothing jsNewObj])
    pure (App Nothing (Function Nothing Nothing [] block) [])

  -- ===== variable refs =====

  varToJs :: Qualified Ident -> AST
  varToJs (Qualified (BySourcePos _) ident) = var ident
  varToJs q = qualifiedToJS identity q

  qualifiedToJS :: forall a. (a -> Ident) -> Qualified a -> AST
  qualifiedToJS f (Qualified (ByModuleName mn') a)
    | mn' == m_Prim = Var Nothing (runIdent (f a))
    | mn /= mn' = ModuleAccessor Nothing mn' (mkString (escapeIdentChars (runIdent (f a))))
    | otherwise = Var Nothing (identToJs (f a))
  qualifiedToJS f (Qualified _ a) = Var Nothing (identToJs (f a))

  escapeIdentChars :: String -> String
  escapeIdentChars s = fold (map identCharToText (SC.toCharArray s))

  foreignIdent :: Ident -> AST
  foreignIdent ident =
    accessorString (mkString (runIdent ident)) (Var Nothing ffiNamespace)

  -- ===== case / binders =====

  bindersToJs :: SourceSpan -> Array (CaseAlternative Ann) -> Array AST -> Supply AST
  bindersToJs ss binders vals = do
    valNames <- traverse (\_ -> freshName) vals
    let assignments =
          zipWith
            (\name v -> VariableIntroduction Nothing name (Just (Tuple UnknownEffects v)))
            valNames
            vals
    jssArr <- traverse (\(CF.CaseAlternative ca) -> do
        ret <- guardsToJs ca.result
        goCaseAlt valNames ret ca.binders) binders
    let jss = Array.concat jssArr
    pure (App Nothing
            (Function Nothing Nothing []
              (Block Nothing
                (assignments <> jss <> [Throw Nothing (failedPatternError valNames)])))
            [])
    where
    failedPatternError :: Array String -> AST
    failedPatternError names =
      Unary Nothing New
        (App Nothing (Var Nothing "Error")
          [ Binary Nothing Add
              (StringLiteral Nothing (mkString failedPatternMessage))
              (ArrayLiteral Nothing (zipWith valueError names vals))
          ])

    failedPatternMessage :: String
    failedPatternMessage =
      "Failed pattern match at " <> runModuleName mn <> " " <> displayStartEndPos ss <> ": "

    displayStartEndPos :: SourceSpan -> String
    displayStartEndPos (SourceSpan sp) =
      "(" <> displaySourcePos sp.start <> " - " <> displaySourcePos sp.end <> ")"

    displaySourcePos :: SourcePos -> String
    displaySourcePos (SourcePos line col) =
      "line " <> show line <> ", column " <> show col

    valueError :: String -> AST -> AST
    valueError _ l@(NumericLiteral _ _) = l
    valueError _ l@(StringLiteral _ _) = l
    valueError _ l@(BooleanLiteral _ _) = l
    valueError s _ =
      accessorString (mkString "name")
        (accessorString (mkString "constructor") (Var Nothing s))

    goCaseAlt :: Array String -> Array AST -> Array (Binder Ann) -> Supply (Array AST)
    goCaseAlt names done bs = case Array.uncons names, Array.uncons bs of
      _, Nothing -> pure done
      Just { head: v, tail: vs }, Just { head: b, tail: bsTail } -> do
        done' <- goCaseAlt vs done bsTail
        binderToJs v done' b
      Nothing, Just _ -> pure done

    guardsToJs :: Either (Array (Tuple (Expr Ann) (Expr Ann))) (Expr Ann) -> Supply (Array AST)
    guardsToJs (Left gs) = traverse (\(Tuple cond val) -> do
        cond' <- valueToJs cond
        val' <- valueToJs val
        pure (IfElse Nothing cond' (Block Nothing [Return Nothing val']) Nothing)) gs
    guardsToJs (Right v) = (\j -> [Return Nothing j]) <$> valueToJs v

  binderToJs :: String -> Array AST -> Binder Ann -> Supply (Array AST)
  binderToJs _ done (CF.NullBinder _) = pure done
  binderToJs s done (CF.LiteralBinder _ l) = literalToBinderJS s done l
  binderToJs s done (CF.VarBinder _ ident) =
    pure (Array.cons
            (VariableIntroduction Nothing (identToJs ident) (Just (Tuple NoEffects (Var Nothing s))))
            done)
  binderToJs s done (CF.ConstructorBinder ann _ ctor binders) = case ann.meta of
    Just CF.IsNewtype -> case Array.head binders of
      Just b -> binderToJs s done b
      Nothing -> pure done
    Just (CF.IsConstructor ctorType fields) -> do
      js <- consBinder s done (zip fields binders)
      pure $ case ctorType of
        CF.ProductType -> js
        CF.SumType ->
          [ IfElse Nothing
              (InstanceOf Nothing (Var Nothing s)
                (qualifiedToJS (\(p :: ProperName) -> Ident (runProperName p)) ctor))
              (Block Nothing js)
              Nothing
          ]
    _ -> pure done  -- shouldn't happen with valid corefn
  binderToJs s done (CF.NamedBinder _ ident inner) = do
    js <- binderToJs s done inner
    pure (Array.cons
            (VariableIntroduction Nothing (identToJs ident) (Just (Tuple NoEffects (Var Nothing s))))
            js)

  consBinder :: String -> Array AST -> Array (Tuple Ident (Binder Ann)) -> Supply (Array AST)
  consBinder s done pairs = goCB done pairs
    where
    goCB acc rest = case Array.uncons rest of
      Nothing -> pure acc
      Just { head: Tuple field binder, tail } -> do
        argVar <- freshName
        acc' <- goCB acc tail
        js <- binderToJs argVar acc' binder
        pure (Array.cons
                (VariableIntroduction Nothing argVar
                  (Just (Tuple UnknownEffects
                    (accessorString (mkString (identToJs field)) (Var Nothing s)))))
                js)

  literalToBinderJS :: String -> Array AST -> Literal (Binder Ann) -> Supply (Array AST)
  literalToBinderJS s done (CF.NumericLiteralInt i) =
    pure [IfElse Nothing
            (Binary Nothing EqualTo (Var Nothing s) (NumericLiteral Nothing (Left i)))
            (Block Nothing done)
            Nothing]
  literalToBinderJS s done (CF.NumericLiteralNumber n) =
    pure [IfElse Nothing
            (Binary Nothing EqualTo (Var Nothing s) (NumericLiteral Nothing (Right n)))
            (Block Nothing done)
            Nothing]
  literalToBinderJS s done (CF.CharLiteral c) =
    pure [IfElse Nothing
            (Binary Nothing EqualTo (Var Nothing s) (StringLiteral Nothing (mkString (Str.singleton (Str.codePointFromChar c)))))
            (Block Nothing done)
            Nothing]
  literalToBinderJS s done (CF.StringLiteral str) =
    pure [IfElse Nothing
            (Binary Nothing EqualTo (Var Nothing s) (StringLiteral Nothing str))
            (Block Nothing done)
            Nothing]
  literalToBinderJS s done (CF.BooleanLiteral true) =
    pure [IfElse Nothing (Var Nothing s) (Block Nothing done) Nothing]
  literalToBinderJS s done (CF.BooleanLiteral false) =
    pure [IfElse Nothing (Unary Nothing Not (Var Nothing s)) (Block Nothing done) Nothing]
  literalToBinderJS s done (CF.ObjectLiteral bs) = goObj done bs
    where
    goObj acc rest = case Array.uncons rest of
      Nothing -> pure acc
      Just { head: Tuple prop b, tail } -> do
        propVar <- freshName
        acc' <- goObj acc tail
        js <- binderToJs propVar acc' b
        pure (Array.cons
                (VariableIntroduction Nothing propVar
                  (Just (Tuple UnknownEffects
                    (accessorString prop (Var Nothing s)))))
                js)
  literalToBinderJS s done (CF.ArrayLiteral bs) = do
    js <- goArr done 0 bs
    pure [IfElse Nothing
            (Binary Nothing EqualTo
              (accessorString (mkString "length") (Var Nothing s))
              (NumericLiteral Nothing (Left (Array.length bs))))
            (Block Nothing js)
            Nothing]
    where
    goArr acc _ rest = case Array.uncons rest of
      Nothing -> pure acc
      Just { head: b, tail } -> do
        elVar <- freshName
        acc' <- goArr acc 0 tail
        js <- binderToJs elVar acc' b
        let idx = Array.length bs - Array.length tail - 1
        pure (Array.cons
                (VariableIntroduction Nothing elVar
                  (Just (Tuple UnknownEffects
                    (Indexer Nothing (NumericLiteral Nothing (Left idx)) (Var Nothing s)))))
                js)

  -- ===== unApp =====

  unApp :: Expr Ann -> Array (Expr Ann) -> { f :: Expr Ann, args :: Array (Expr Ann) }
  unApp (CF.App _ v a) acc = unApp v (Array.cons a acc)
  unApp other acc = { f: other, args: acc }

  curryApp :: AST -> AST -> AST
  curryApp f a = App Nothing f [a]

-- placeholder removed; correct ordNub lives at top level below

-- | nub preserving insertion order.
ordNub :: forall a. Ord a => Array a -> Array a
ordNub = go Set.empty []
  where
  go seen acc arr = case Array.uncons arr of
    Nothing -> Array.reverse acc
    Just { head, tail }
      | Set.member head seen -> go seen acc tail
      | otherwise -> go (Set.insert head seen) (Array.cons head acc) tail

arrayDifference :: forall a. Eq a => Array a -> Array a -> Array a
arrayDifference xs ys = Array.filter (\x -> not (Array.elem x ys)) xs

catMaybes :: forall a. Array (Maybe a) -> Array a
catMaybes = Array.mapMaybe identity

-- | Helper used everywhere: indexer with string literal property.
accessorString :: PSString -> AST -> AST
accessorString prop val = Indexer Nothing (StringLiteral Nothing prop) val

-- | annotatePure: add /* #__PURE__ */ markers to side-effect-free top-level
-- | declarations. Currently a no-op fallback; pure-marking the simple cases
-- | matches the bundler-hint behavior of the Haskell compiler.
annotatePure :: AST -> AST
annotatePure ast = case maybePure false ast of
  Just j -> j
  Nothing -> pureIife ast

pureIife :: AST -> AST
pureIife val =
  Comment PureAnnotation
    (App Nothing
      (Function Nothing Nothing [] (Block Nothing [Return Nothing val]))
      [])

pureApp :: forall a. Maybe a -> AST -> Array AST -> AST
pureApp _ f args = Comment PureAnnotation (App Nothing f args)

maybePure :: Boolean -> AST -> Maybe AST
maybePure alreadyAnnotated = case _ of
  VariableIntroduction ss name (Just (Tuple eff inner)) ->
    Just (VariableIntroduction ss name (Just (Tuple eff (annotatePure inner))))
  VariableIntroduction ss name Nothing ->
    Just (VariableIntroduction ss name Nothing)
  App ss f args -> do
    f' <- maybePure true f
    args' <- traverse (maybePure false) args
    Just $ if alreadyAnnotated
      then App ss f' args'
      else Comment PureAnnotation (App ss f' args')
  ArrayLiteral ss xs ->
    ArrayLiteral ss <$> traverse (maybePure false) xs
  ObjectLiteral ss ps ->
    ObjectLiteral ss <$> traverse (\(Tuple k v) -> Tuple k <$> maybePure false v) ps
  Comment c j -> Comment c <$> maybePure false j
  -- A `Indexer of (Var FFINamespace)` is allowed
  j@(Indexer _ _ (Var _ name)) | name == ffiNamespace -> Just j
  j@(NumericLiteral _ _) -> Just j
  j@(StringLiteral _ _) -> Just j
  j@(BooleanLiteral _ _) -> Just j
  j@(Function _ _ _ _) -> Just j
  j@(Var _ _) -> Just j
  j@(ModuleAccessor _ _ _) -> Just j
  _ -> Nothing

-- | Walk the AST, replacing ModuleAccessor with Indexer of (Var alias).
-- | Returns the new body and the set of module names that were referenced.
type WalkResult =
  { body :: Array AST
  , usedModules :: Set ModuleName
  }

walkModule :: Map ModuleName String -> Array AST -> WalkResult
walkModule lookup body =
  let r = foldr step { body: [], usedModules: Set.empty } body
  in r
  where
  step a acc =
    let r = walkAST lookup a
    in { body: Array.cons r.ast acc.body
       , usedModules: Set.union r.usedModules acc.usedModules
       }

walkAST :: Map ModuleName String -> AST -> { ast :: AST, usedModules :: Set ModuleName }
walkAST lookup = go
  where
  go (ModuleAccessor _ mn name) =
    let alias = fromMaybe (moduleNameToJs mn) (Map.lookup mn lookup)
    in { ast: accessorString name (Var Nothing alias)
       , usedModules: Set.singleton mn
       }
  go (Unary ss op j) =
    let r = go j
    in { ast: Unary ss op r.ast, usedModules: r.usedModules }
  go (Binary ss op j1 j2) =
    let r1 = go j1
        r2 = go j2
    in { ast: Binary ss op r1.ast r2.ast
       , usedModules: Set.union r1.usedModules r2.usedModules
       }
  go (ArrayLiteral ss js) =
    let rs = map go js
    in { ast: ArrayLiteral ss (map _.ast rs)
       , usedModules: foldl Set.union Set.empty (map _.usedModules rs)
       }
  go (Indexer ss j1 j2) =
    let r1 = go j1
        r2 = go j2
    in { ast: Indexer ss r1.ast r2.ast
       , usedModules: Set.union r1.usedModules r2.usedModules
       }
  go (ObjectLiteral ss ps) =
    let rs = map (\(Tuple k v) -> Tuple k (go v)) ps
    in { ast: ObjectLiteral ss (map (\(Tuple k r) -> Tuple k r.ast) rs)
       , usedModules: foldl Set.union Set.empty (map (\(Tuple _ r) -> r.usedModules) rs)
       }
  go (Function ss name args j) =
    let r = go j
    in { ast: Function ss name args r.ast, usedModules: r.usedModules }
  go (App ss j js) =
    let r = go j
        rs = map go js
    in { ast: App ss r.ast (map _.ast rs)
       , usedModules: foldl Set.union r.usedModules (map _.usedModules rs)
       }
  go (Block ss js) =
    let rs = map go js
    in { ast: Block ss (map _.ast rs)
       , usedModules: foldl Set.union Set.empty (map _.usedModules rs)
       }
  go (VariableIntroduction ss name Nothing) =
    { ast: VariableIntroduction ss name Nothing, usedModules: Set.empty }
  go (VariableIntroduction ss name (Just (Tuple eff j))) =
    let r = go j
    in { ast: VariableIntroduction ss name (Just (Tuple eff r.ast))
       , usedModules: r.usedModules
       }
  go (Assignment ss j1 j2) =
    let r1 = go j1
        r2 = go j2
    in { ast: Assignment ss r1.ast r2.ast
       , usedModules: Set.union r1.usedModules r2.usedModules
       }
  go (While ss j1 j2) =
    let r1 = go j1
        r2 = go j2
    in { ast: While ss r1.ast r2.ast
       , usedModules: Set.union r1.usedModules r2.usedModules
       }
  go (For ss name j1 j2 j3) =
    let r1 = go j1
        r2 = go j2
        r3 = go j3
    in { ast: For ss name r1.ast r2.ast r3.ast
       , usedModules: foldl Set.union Set.empty [r1.usedModules, r2.usedModules, r3.usedModules]
       }
  go (ForIn ss name j1 j2) =
    let r1 = go j1
        r2 = go j2
    in { ast: ForIn ss name r1.ast r2.ast
       , usedModules: Set.union r1.usedModules r2.usedModules
       }
  go (IfElse ss j1 j2 j3) =
    let r1 = go j1
        r2 = go j2
        r3 = map go j3
    in { ast: IfElse ss r1.ast r2.ast (map _.ast r3)
       , usedModules: foldl Set.union Set.empty
           [r1.usedModules, r2.usedModules, maybe Set.empty _.usedModules r3]
       }
  go (Return ss j) =
    let r = go j
    in { ast: Return ss r.ast, usedModules: r.usedModules }
  go r@(ReturnNoResult _) = { ast: r, usedModules: Set.empty }
  go (Throw ss j) =
    let r = go j
    in { ast: Throw ss r.ast, usedModules: r.usedModules }
  go (InstanceOf ss j1 j2) =
    let r1 = go j1
        r2 = go j2
    in { ast: InstanceOf ss r1.ast r2.ast
       , usedModules: Set.union r1.usedModules r2.usedModules
       }
  go (Comment c j) =
    let r = go j
    in { ast: Comment c r.ast, usedModules: r.usedModules }
  go other = { ast: other, usedModules: Set.empty }
