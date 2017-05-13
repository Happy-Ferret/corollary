




module Language.Rust.Corrode.C (interpretTranslationUnit) where{

import Control.Monad
;import Control.Monad.ST
;import Control.Monad.Trans.Class
;import Control.Monad.Trans.Except
;import Control.Monad.Trans.RWS.Strict
;import Data.Foldable
;import qualified Data.Map.Lazy as Map
;import qualified Data.IntMap.Strict as IntMap
;import Data.Maybe
;import Data.List
;import Data.STRef
;import qualified Data.Set as Set
;import Language.C
;import Language.C.Data.Ident
;import qualified Language.Rust.AST as Rust
;import Language.Rust.Corrode.CFG
;import Language.Rust.Corrode.CrateMap
;import Text.PrettyPrint.HughesPJClass hiding (Pretty)



;type EnvMonad s = ExceptT String (RWST FunctionContext Output (EnvState s) (ST s))



;data FunctionContext = FunctionContext
    { functionReturnType :: Maybe CType
    , functionName :: Maybe String
    , itemRewrites :: ItemRewrites
    }



;data Output = Output
    { outputItems :: [Rust.Item]
    , outputExterns :: Map.Map String Rust.ExternItem
    , outputIncomplete :: Set.Set String
    }



;instance Monoid Output where{



        mempty = Output
             { outputItems = mempty
             , outputExterns = mempty
             , outputIncomplete = mempty
             }
     
 
 
         ;mappend a b = Output
             { outputItems = outputItems a `mappend` outputItems b
             , outputExterns = outputExterns a `mappend` outputExterns b
             , outputIncomplete = outputIncomplete a `mappend` outputIncomplete b
             }
     
 
 
 };emitItems :: [Rust.Item] -> EnvMonad s ()
;emitItems items = lift $ tell mempty { outputItems = items }



;emitIncomplete :: ItemKind -> Ident -> EnvMonad s CType
;emitIncomplete kind ident = do{
    rewrites <- lift (asks itemRewrites)
     ;unless (Map.member (kind, identToString ident) rewrites) $
         lift $ tell mempty { outputIncomplete = Set.singleton (identToString ident) }
     ;return (IsIncomplete ident)
 
 
 
 };completeType :: CType -> EnvMonad s CType
;completeType orig@(IsIncomplete ident) = do{
    mty <- getTagIdent ident
     ;fromMaybe (return orig) mty
 };completeType ty = return ty



;data GlobalState = GlobalState
    { unique :: Int
    , usedForwardRefs :: Set.Set Ident
    }



;uniqueName :: String -> EnvMonad s String
;uniqueName base = modifyGlobal $ \ st ->
    (st { unique = unique st + 1 }, base ++ show (unique st))



;useForwardRef :: Ident -> EnvMonad s ()
;useForwardRef ident = modifyGlobal $ \ st ->
    (st { usedForwardRefs = Set.insert ident (usedForwardRefs st) }, ())



;data EnvState s = EnvState
    { symbolEnvironment :: [(Ident, EnvMonad s Result)]
    , typedefEnvironment :: [(Ident, EnvMonad s IntermediateType)]
    , tagEnvironment :: [(Ident, EnvMonad s CType)]
    , globalState :: GlobalState
    }



;modifyGlobal :: (GlobalState -> (GlobalState, a)) -> EnvMonad s a
;modifyGlobal f = lift $ do{
    st <- get
     ;let{ (global', a) = f (globalState st)
      ;return a
  
  
  
  }};applyRenames :: Ident -> String
;applyRenames ident = case identToString ident of{
    "ZmluYWw=" -> "ZmluYWxf"
     ;"Zm4=" -> "Zm5f"
     ;"aW4=" -> "aW5f"
     ;"bGV0" -> "bGV0Xw=="
     ;"bWFpbg==" -> "X2NfbWFpbg=="
     ;"bWF0Y2g=" -> "bWF0Y2hf"
     ;"bW9k" -> "bW9kXw=="
     ;"cHJvYw==" -> "cHJvY18="
     ;"dHlwZQ==" -> "dHlwZV8="
     ;"d2hlcmU=" -> "d2hlcmVf"
     ;name -> name
 
 
 
 };getSymbolIdent :: Ident -> EnvMonad s (Maybe Result)
;getSymbolIdent ident = do{
    env <- lift get
     ;case lookup ident (symbolEnvironment env) of{
         Just symbol -> fmap Just symbol
          ;Nothing -> case identToString ident of{
              "X19mdW5jX18=" -> getFunctionName ""
               ;"X19GVU5DVElPTl9f" -> getFunctionName ""
               ;"X19QUkVUVFlfRlVOQ1RJT05fXw==" -> getFunctionName "dG9wIGxldmVs"
               ;name -> return $ lookup name builtinSymbols
       }};where{
     getFunctionName def = do{
          name <- lift (asks functionName)
           ;return $ Just Result
               { resultType = IsArray Rust.Immutable (length name' + 1) charType
               , resultMutable = Rust.Immutable
               , result = Rust.Deref (Rust.Lit (Rust.LitByteStr (name' ++ "MA==")))
               }
       };builtinSymbols =
          [ ("X19idWlsdGluX2Jzd2Fw" ++ show w, Result
              { resultType = IsFunc (IsInt Unsigned (BitWidth w))
                  [(Nothing, IsInt Unsigned (BitWidth w))] False
              , resultMutable = Rust.Immutable
              , result = Rust.Path (Rust.PathSegments ["dQ==" ++ show w, "c3dhcF9ieXRlcw=="])
              })
          | w <- [16, 32, 64]
          ]
          ++
          [ ("X19GSUxFX18=", Result
              { resultType = IsPtr Rust.Immutable charType
              , resultMutable = Rust.Immutable
              , result = Rust.MethodCall (
                      Rust.Call (Rust.Var (Rust.VarName "ZmlsZSE=")) []
                  ) (Rust.VarName "YXNfcHRy") []
              })
          , ("X19MSU5FX18=", Result
              { resultType = IsInt Unsigned (BitWidth 32)
              , resultMutable = Rust.Immutable
              , result = Rust.Call (Rust.Var (Rust.VarName "bGluZSE=")) []
              })
          ]
  
  }};getTypedefIdent :: Ident -> EnvMonad s (String, Maybe (EnvMonad s IntermediateType))
;getTypedefIdent ident = lift $ do{
    env <- gets typedefEnvironment
     ;return (identToString ident, lookup ident env)
 
 };getTagIdent :: Ident -> EnvMonad s (Maybe (EnvMonad s CType))
;getTagIdent ident = lift $ do{
    env <- gets tagEnvironment
     ;return $ lookup ident env
 
 
 
 };addSymbolIdent :: Ident -> (Rust.Mutable, CType) -> EnvMonad s String
;addSymbolIdent ident (mut, ty) = do{
    let{ name = applyRenames ident
      ;return name
  
  }};addSymbolIdentAction :: Ident -> EnvMonad s Result -> EnvMonad s ()
;addSymbolIdentAction ident action = lift $ do{
    modify $ \ st -> st { symbolEnvironment = (ident, action) : symbolEnvironment st }
 
 };addTypedefIdent :: Ident -> EnvMonad s IntermediateType -> EnvMonad s ()
;addTypedefIdent ident ty = lift $ do{
    modify $ \ st -> st { typedefEnvironment = (ident, ty) : typedefEnvironment st }
 
 };addTagIdent :: Ident -> EnvMonad s CType -> EnvMonad s ()
;addTagIdent ident ty = lift $ do{
    modify $ \ st -> st { tagEnvironment = (ident, ty) : tagEnvironment st }
 
 
 
 };addExternIdent
    :: Ident
    -> EnvMonad s IntermediateType
    -> (String -> (Rust.Mutable, CType) -> Rust.ExternItem)
    -> EnvMonad s ()
;addExternIdent ident deferred mkItem = do{
    action <- runOnce $ do{
         itype <- deferred
          ;rewrites <- lift $ asks itemRewrites
          ;path <- case Map.lookup (Symbol, identToString ident) rewrites of{
              Just renamed -> return ("" : renamed)
               ;Nothing -> do{
                   lift $ tell mempty { outputExterns = Map.singleton name (mkItem name ty) }
                    ;return [name]
            }};return (typeToResult itype (Rust.Path (Rust.PathSegments path)))
      };addSymbolIdentAction ident action
 
 
 
 };noTranslation :: (Pretty node, Pos node) => node -> String -> EnvMonad s a
;noTranslation node msg = throwE $ concat
    [ show (posOf node)
    , "OiA="
    , msg
    , "Olxu"
    , render (nest 4 (pretty node))
    ]



;unimplemented :: (Pretty node, Pos node) => node -> EnvMonad s a
;unimplemented node = noTranslation node "Q29ycm9kZSBkb2Vzbid0IGhhbmRsZSB0aGlzIHlldA=="



;badSource :: (Pretty node, Pos node) => node -> String -> EnvMonad s a
;badSource node msg = noTranslation node
    ("aWxsZWdhbCA=" ++ msg ++ "OyBjaGVjayB3aGV0aGVyIGEgcmVhbCBDIGNvbXBpbGVyIGFjY2VwdHMgdGhpcw==")



;interpretTranslationUnit :: ModuleMap -> ItemRewrites -> CTranslUnit -> Either String [Rust.Item]
;interpretTranslationUnit _thisModule rewrites (CTranslUnit decls _) = case err of{
    Left msg -> Left msg
     ;Right _ -> Right items'
     ;where{
 
 
 
     initFlow = FunctionContext
          { functionReturnType = Nothing
          , functionName = Nothing
          , itemRewrites = rewrites
          }
      ;initState = EnvState
          { symbolEnvironment = []
          , typedefEnvironment = []
          , tagEnvironment = []
          , globalState = GlobalState
              { unique = 1
              , usedForwardRefs = Set.empty
              }
          }
      ;(err, output) = runST (evalRWST (runExceptT (mapM_ perDecl decls)) initFlow initState)
  
  
  
      ;perDecl (CFDefExt f) = interpretFunction f
      ;perDecl (CDeclExt decl') = do{
          binds <- interpretDeclarations makeStaticBinding decl'
           ;emitItems binds
       };perDecl decl = unimplemented decl
  
  
  
      ;completeTypes = Set.fromList $ catMaybes
          [ case item of{
              Rust.Item _ _ (Rust.Struct name _) -> Just name
               ;_ -> Nothing
           }| item <- outputItems output
          ]
      ;incompleteTypes = outputIncomplete output `Set.difference` completeTypes
      ;incompleteItems =
          [ Rust.Item [] Rust.Private (Rust.Enum name [])
          | name <- Set.toList incompleteTypes
          ]
  
  
  
      ;itemNames = catMaybes
          [ case item of{
              Rust.Item _ _ (Rust.Function _ name _ _ _) -> Just name
               ;Rust.Item _ _ (Rust.Static _ (Rust.VarName name) _ _) -> Just name
               ;_ -> Nothing
           }| item <- outputItems output
          ]
  
      ;externs' =
          [ extern
          | (name, extern) <- Map.toList (outputExterns output)
          , name `notElem` itemNames
          ]
  
  
  
      ;items = incompleteItems ++ outputItems output
  
  
  
      ;items' = if null externs'
          then items
          else Rust.Item [] Rust.Private (Rust.Extern externs') : items
  
  
  
  }};type MakeBinding s a = (Rust.ItemKind -> a, Rust.Mutable -> Rust.Var -> CType -> NodeInfo -> Maybe CInit -> EnvMonad s a)



;makeStaticBinding :: MakeBinding s Rust.Item
;makeStaticBinding = (Rust.Item [] Rust.Private, makeBinding)
    where{
    makeBinding mut var ty node minit = do{
         expr <- interpretInitializer ty (fromMaybe (CInitList [] node) minit)
          ;return $ Rust.Item attrs Rust.Public
              (Rust.Static mut var (toRustType ty) expr)
      };attrs = [Rust.Attribute "bm9fbWFuZ2xl"]
 
 };makeLetBinding :: MakeBinding s Rust.Stmt
;makeLetBinding = (Rust.StmtItem [], makeBinding)
    where{
    makeBinding mut var ty _ minit = do{
         mexpr <- mapM (interpretInitializer ty) minit
          ;return $ Rust.Let mut var (Just (toRustType ty)) mexpr
  
  
  
  }};interpretDeclarations :: MakeBinding s b -> CDecl -> EnvMonad s [b]
;interpretDeclarations (fromItem, makeBinding) declaration@(CDecl specs decls _) = do{



    (storagespecs, baseTy) <- baseTypeOf specs
 
 
 
     ;mbinds <- forM decls $ \ declarator -> do{
 
 
 
         (decl, minit) <- case declarator of{
              (Just decl, minit, Nothing) -> return (decl, minit)
               ;(Nothing, _, _) -> badSource declaration "YWJzZW50IGRlY2xhcmF0b3I="
               ;(_, _, Just _) -> badSource declaration "Yml0ZmllbGQgZGVjbGFyYXRvcg=="
   
           
           };(ident, derived) <- case decl of{
              CDeclr (Just ident) derived _ _ _ -> return (ident, derived)
               ;_ -> badSource decl "YWJzdHJhY3QgZGVjbGFyYXRvcg=="
   
           };deferred <- derivedDeferredTypeOf baseTy decl []
          ;case (storagespecs, derived) of{
  
  
  
              (Just (CTypedef _), _) -> do{
                   when (isJust minit) (badSource decl "aW5pdGlhbGl6ZXIgb24gdHlwZWRlZg==")
                    ;addTypedefIdent ident deferred
                    ;return Nothing
    
    
    
                };(Just (CStatic _), CFunDeclr{} : _) -> do{
                   addSymbolIdentAction ident $ do{
                        itype <- deferred
                         ;useForwardRef ident
                         ;return (typeToResult itype (Rust.Path (Rust.PathSegments [applyRenames ident])))
                     };return Nothing
    
    
    
                };(_, CFunDeclr{} : _) -> do{
                   addExternIdent ident deferred $ \ name (_mut, ty) -> case ty of{
                        IsFunc retTy args variadic ->
                             let{ formals =
                                      [ (Rust.VarName argName, toRustType argTy)
                                      | (idx, (mname, argTy)) <- zip [1 :: Int ..] args
                                      , let{ argName = maybe ("YXJn" ++ show idx) (applyRenames . snd) mname
                                       }]
                              ;in Rust.ExternFn name formals variadic (toRustRetType retTy)
                          };_ -> error (show ident ++ "IGlzIGJvdGggYSBmdW5jdGlvbiBhbmQgbm90IGEgZnVuY3Rpb24/")
                     };return Nothing
    
    
    
                };(Just (CExtern _), _) -> do{
                   addExternIdent ident deferred $ \ name (mut, ty) ->
                        Rust.ExternStatic mut (Rust.VarName name) (toRustType ty)
                    ;return Nothing
    
    
    
                };(Just (CStatic _), _) -> do{
                   IntermediateType
                        { typeMutable = mut
                        , typeRep = ty } <- deferred
                    ;name <- addSymbolIdent ident (mut, ty)
                    ;expr <- interpretInitializer ty (fromMaybe (CInitList [] (nodeInfo decl)) minit)
                    ;return (Just (fromItem
                        (Rust.Static mut (Rust.VarName name) (toRustType ty) expr)))
    
    
    
                };_ -> do{
                   IntermediateType
                        { typeMutable = mut
                        , typeRep = ty } <- deferred
                    ;name <- addSymbolIdent ident (mut, ty)
                    ;binding <- makeBinding mut (Rust.VarName name) ty (nodeInfo decl) minit
                    ;return (Just binding)
    
    
    
        }}};return (catMaybes mbinds)
 
 
 
 };interpretDeclarations _ node@(CStaticAssert {}) = unimplemented node



;interpretInitializer :: CType -> CInit -> EnvMonad s Rust.Expr



;data Initializer
    = Initializer (Maybe Rust.Expr) (IntMap.IntMap Initializer)



;scalar :: Rust.Expr -> Initializer
;scalar expr = Initializer (Just expr) IntMap.empty



;instance Monoid Initializer where{



        mempty = Initializer Nothing IntMap.empty
     
 
 
         ;mappend _ b@(Initializer (Just _) _) = b
         ;mappend (Initializer m a) (Initializer Nothing b) =
             Initializer m (IntMap.unionWith mappend a b)
     
 
 
 };type CurrentObject = Maybe Designator

;data Designator
  = Base CType



  | From CType Int [CType] Designator
  deriving(Show)



;designatorType :: Designator -> CType
;designatorType (Base ty) = ty
;designatorType (From ty _ _ _) = ty



;objectFromDesignators :: CType -> [CDesignator] -> EnvMonad s CurrentObject
;objectFromDesignators _ [] = pure Nothing
;objectFromDesignators ty desigs = Just <$> go ty desigs (Base ty)
    where{

    go :: CType -> [CDesignator] -> Designator -> EnvMonad s Designator
     ;go _ [] obj = pure obj
     ;go (IsArray _ size el) (CArrDesig idxExpr _ : ds) obj = do{
         idx <- interpretConstExpr idxExpr
          ;go el ds (From el (fromInteger idx) (replicate (size - fromInteger idx - 1) el) obj)
      };go (IsStruct name fields) (d@(CMemberDesig ident _) : ds) obj = do{
         case span (\ (field, _) -> applyRenames ident /= field) fields of{
              (_, []) -> badSource d ("ZGVzaWduYXRvciBmb3IgZmllbGQgbm90IGluIHN0cnVjdCA=" ++ name)
               ;(earlier, (_, ty') : rest) ->
                   go ty' ds (From ty' (length earlier) (map snd rest) obj)
       }};go ty' (d : _) _ = badSource d ("ZGVzaWduYXRvciBmb3Ig" ++ show ty')
 
 
 
 };nextObject :: Designator -> CurrentObject
;nextObject Base{} = Nothing
;nextObject (From _ i (ty : remaining) base) = Just (From ty (i+1) remaining base)
;nextObject (From _ _ [] base) = nextObject base



;compatibleInitializer :: CType -> CType -> Bool
;compatibleInitializer (IsStruct name1 _) (IsStruct name2 _) = name1 == name2
;compatibleInitializer IsStruct{} _ = False
;compatibleInitializer _ IsStruct{} = False
;compatibleInitializer _ _ = True



;nestedObject :: CType -> Designator -> Maybe Designator
;nestedObject ty desig = case designatorType desig of{
    IsArray _ size el -> Just (From el 0 (replicate (size - 1) el) desig)
     ;ty' | ty `compatibleInitializer` ty' -> Just desig
     ;IsStruct _ ((_ , ty') : fields) ->
         nestedObject ty (From ty' 0 (map snd fields) desig)
     ;_ -> Nothing
 
 
 
 };translateInitList :: CType -> CInitList -> EnvMonad s Initializer
;translateInitList ty list = do{

    objectsAndInitializers <- forM list $ \ (desigs, initial) -> do{
         currObj <- objectFromDesignators ty desigs
          ;pure (currObj, initial)
  
  
  
      };let{ base = case ty of{
                      IsArray _ size el -> From el 0 (replicate (size - 1) el) (Base ty)
                       ;IsStruct _ ((_,ty'):fields) -> From ty' 0 (map snd fields) (Base ty)
                       ;_ -> Base ty
   
   
   
   }}};resolveCurrentObject
    :: (CurrentObject, Initializer)
    -> (CurrentObject, CInit)
    -> EnvMonad s (CurrentObject, Initializer)
;resolveCurrentObject (obj0, prior) (obj1, cinitial) = case obj1 `mplus` obj0 of{
    Nothing -> return (Nothing, prior)
     ;Just obj -> do{
 
 
 
         (obj', initial) <- case cinitial of{
              CInitList list' _ -> do{
                   initial <- translateInitList (designatorType obj) list'
                    ;return (obj, initial)
                };CInitExpr expr _ -> do{
                   expr' <- interpretExpr True expr
                    ;case nestedObject (resultType expr') obj of{
                        Nothing -> badSource cinitial "dHlwZSBpbiBpbml0aWFsaXplcg=="
                         ;Just obj' -> do{
                             let{ s = castTo (designatorType obj') expr'
                               ;return (obj', scalar s)
       
       
       
               }}}}};return (nextObject obj', prior `mappend` initializer)
  
  
  
  }};interpretInitializer ty initial = do{
    initial' <- case initial of{
         CInitExpr expr _ -> do{
              expr' <- interpretExpr True expr
               ;if resultType expr' `compatibleInitializer` ty
                   then pure $ scalar (castTo ty expr')
                   else badSource initial "aW5pdGlhbGl6ZXIgZm9yIGluY29tcGF0aWJsZSB0eXBl"
           };CInitList list _ -> translateInitList ty list
  
      };zeroed <- zeroInitialize initial' ty
     ;helper ty zeroed
 
     ;where{
 
 
 
     zeroInitialize i@(Initializer Nothing initials) origTy = completeType origTy >>= \ t -> case t of{
          IsBool{} -> return $ scalar (Rust.Lit (Rust.LitBool False))
           ;IsVoid{} -> badSource initial "aW5pdGlhbGl6ZXIgZm9yIHZvaWQ="
           ;IsInt{} -> return $ scalar (Rust.Lit (Rust.LitInt 0 Rust.DecRepr (toRustType t)))
           ;IsFloat{} -> return $ scalar (Rust.Lit (Rust.LitFloat "MA==" (toRustType t)))
           ;IsPtr{} -> return $ scalar (Rust.Cast 0 (toRustType t))
           ;IsArray _ size _ | IntMap.size initials == size -> return i
           ;IsArray _ size elTy -> do{
               elInit <- zeroInitialize (Initializer Nothing IntMap.empty) elTy
                ;el <- helper elTy elInit
                ;return (Initializer (Just (Rust.RepeatArray el (fromIntegral size))) initials)
            };IsFunc{} -> return $ scalar (Rust.Cast 0 (toRustType t))
           ;IsStruct _ fields -> do{
               let{ fields' = IntMap.fromDistinctAscList $ zip [0..] $ map snd fields
                 ;let{ missing = fields' `IntMap.difference` initials
                  ;zeros <- mapM (zeroInitialize (Initializer Nothing IntMap.empty)) missing
                  ;return (Initializer Nothing (IntMap.union initials zeros))
              }}};IsEnum{} -> unimplemented initial
           ;IsIncomplete _ -> badSource initial "aW5pdGlhbGl6YXRpb24gb2YgaW5jb21wbGV0ZSB0eXBl"
       };zeroInitialize i _ = return i
  
  
  
      ;helper _ (Initializer (Just expr) initials) | IntMap.null initials = return expr
      ;helper (IsArray _ _ el) (Initializer expr initials) = case expr of{
          Nothing -> Rust.ArrayExpr <$> mapM (helper el) (IntMap.elems initials)
           ;Just _ -> unimplemented initial
       };helper strTy@(IsStruct str fields) (Initializer expr initials) =
          Rust.StructExpr str <$> fields' <*> pure expr
          where{
          fields' = forM (IntMap.toList initials) $ \ (idx, value) ->
               case drop idx fields of{
               (field, ty') : _ -> do{
                    value' <- helper ty' value
                     ;return (field, value')
                 };[] -> noTranslation initial ("aW50ZXJuYWwgZXJyb3I6IA==" ++ show strTy ++ "IGRvZXNuJ3QgaGF2ZSBlbm91Z2ggZmllbGRzIHRvIGluaXRpYWxpemUgZmllbGQg" ++ show idx)
        }};helper _ _ = badSource initial "aW5pdGlhbGl6ZXI="
  
  
  
  }};interpretFunction :: CFunDef -> EnvMonad s ()
;interpretFunction (CFunDef specs declr@(CDeclr mident _ _ _ _) argtypes body _) = do{



    (storage, baseTy) <- baseTypeOf specs
     ;(attrs, vis) <- case storage of{
         Nothing -> return ([Rust.Attribute "bm9fbWFuZ2xl"], Rust.Public)
          ;Just (CStatic _) -> return ([], Rust.Private)
          ;Just s -> badSource s "c3RvcmFnZSBjbGFzcyBzcGVjaWZpZXIgZm9yIGZ1bmN0aW9u"
  
  
  
      };let{ go name funTy = do{
  
  
  
              (retTy, args) <- case funTy of{
                   IsFunc _ _ True -> unimplemented declr
                    ;IsFunc retTy args False -> return (retTy, args)
                    ;_ -> badSource declr "ZnVuY3Rpb24gZGVmaW5pdGlvbg=="
    
    
    
                };when (name == "X2NfbWFpbg==") (wrapMain declr name (map snd args))
   
   
   
               ;let{ setRetTy flow = flow
                        { functionReturnType = Just retTy
                        , functionName = Just name
                        }
                ;f' <- mapExceptT (local setRetTy) $ scope $ do{
    
    
    
                    formals <- sequence
                         [ case arg of{
                             Just (mut, argident) -> do{
                                  argname <- addSymbolIdent argident (mut, ty)
                                   ;return (mut, Rust.VarName argname, toRustType ty)
                               };Nothing -> badSource declr "YW5vbnltb3VzIHBhcmFtZXRlcg=="
                          }| (arg, ty) <- args
                         ]
     
     
     
     
     
     
                     ;body' <- cfgToRust declr (interpretStatement body (return ([returnStatement], Unreachable)))
     
     
     
                     ;return (Rust.Item attrs vis
                         (Rust.Function [Rust.UnsafeFn, Rust.ExternABI Nothing] name formals (toRustRetType retTy)
                             (statementsToBlock body')))
     
                 };emitItems [f']
    
    
    
        }};ident <- case mident of{
          Nothing -> badSource declr "YW5vbnltb3VzIGZ1bmN0aW9uIGRlZmluaXRpb24="
           ;Just ident -> return ident
   
       };let{ name = applyRenames ident
       ;let{ funTy itype = typeToResult itype (Rust.Path (Rust.PathSegments [name]))
        ;deferred <- fmap (fmap funTy) (derivedDeferredTypeOf baseTy declr argtypes)
        ;alreadyUsed <- lift $ gets (usedForwardRefs . globalState)
        ;case vis of{
            Rust.Private | ident `Set.notMember` alreadyUsed -> do{
                 action <- runOnce $ do{
                      ty <- deferred
                       ;go name (resultType ty)
                       ;return ty
                   };addSymbolIdentAction ident action
              };_ -> do{
                 ty <- deferred
                  ;addSymbolIdentAction ident $ return ty
                  ;go name (resultType ty)
      
      
      
      }}}}}};wrapMain :: CDeclr -> String -> [CType] -> EnvMonad s ()
;wrapMain declr realName argTypes = do{



    (setup, args) <- wrapArgv argTypes
 
 
 
     ;let{ ret = Rust.VarName "cmV0"
      ;emitItems [Rust.Item [] Rust.Private (
          Rust.Function [] "bWFpbg==" [] (Rust.TypeName "KCk=") (statementsToBlock (
              setup ++
              [ bind Rust.Immutable ret $
                  Rust.UnsafeExpr $ Rust.Block [] $ Just $
                  call realName args ] ++
              exprToStatements (call "OjpzdGQ6OnByb2Nlc3M6OmV4aXQ=" [Rust.Var ret])
          )))]
      ;where{
  
  
  
          bind mut var val = Rust.Let mut var Nothing (Just val)
       
   
   
           ;call fn args = Rust.Call (Rust.Var (Rust.VarName fn)) args
       
   
   
           ;chain method args obj = Rust.MethodCall obj (Rust.VarName method) args
       
   
   
       };wrapArgv [] = return ([], [])
  
  
  
      ;wrapArgv (argcType@(IsInt Signed (BitWidth 32))) do{
          (envSetup, envArgs) <- wrapEnvp rest
           ;return (setup ++ envSetup, args ++ envArgs)
           ;where{
           argv_storage = Rust.VarName "YXJndl9zdG9yYWdl"
            ;argv = Rust.VarName "YXJndg=="
            ;str = Rust.VarName "c3Ry"
            ;vec = Rust.VarName "dmVj"
            ;setup =
    
    
    
                [ Rust.StmtItem [] (Rust.Use "OjpzdGQ6Om9zOjp1bml4OjpmZmk6Ok9zU3RyaW5nRXh0")
                , bind Rust.Mutable argv_storage $
                    chain "Y29sbGVjdDo6PFZlYzxfPj4=" [] $
                    chain "bWFw" [
                        Rust.Lambda [str] (Rust.BlockExpr (Rust.Block
                            ( bind Rust.Mutable vec (chain "aW50b192ZWM=" [] (Rust.Var str))
                            : exprToStatements (chain "cHVzaA==" [
                                    Rust.Lit (Rust.LitByteChar '0')
                                ] (Rust.Var vec))
                            ) (Just (Rust.Var vec))))
                    ] $
                    call "OjpzdGQ6OmVudjo6YXJnc19vcw==" []
    
    
    
                , bind Rust.Mutable argv $
                    chain "Y29sbGVjdDo6PFZlYzxfPj4=" [] $
                    chain "Y2hhaW4=" [call "U29tZQ==" [call "OjpzdGQ6OnB0cjo6bnVsbF9tdXQ=" []]] $
                    chain "bWFw" [
                        Rust.Lambda [vec] (chain "YXNfbXV0X3B0cg==" [] (Rust.Var vec))
                    ] $
                    chain "aXRlcl9tdXQ=" [] $
                    Rust.Var argv_storage
                ]
    
    
    
            ;args =
                [ Rust.Cast (chain "bGVu" [] (Rust.Var argv_storage)) (toRustType argcType)
                , chain "YXNfbXV0X3B0cg==" [] (Rust.Var argv)
                ]
    
    
    
        }};wrapArgv _ = unimplemented declr
  
  
  
      ;wrapEnvp [] = return ([], [])
      ;wrapEnvp _ = unimplemented declr
  
  
  
  }};data OuterLabels = OuterLabels
    { onBreak :: Maybe Label
    , onContinue :: Maybe Label
    , switchExpression :: Maybe CExpr
    }

;newtype SwitchCases = SwitchCases (IntMap.IntMap (Maybe Result))




;type CSourceBuildCFGT s = BuildCFGT (RWST OuterLabels SwitchCases (Map.Map Ident Label) (EnvMonad s)) [Rust.Stmt] Result

;interpretStatement :: CStat -> CSourceBuildCFGT s ([Rust.Stmt], Terminator Result) -> CSourceBuildCFGT s ([Rust.Stmt], Terminator Result)



;interpretStatement (CLabel ident body _ _) next = do{
    label <- gotoLabel ident
     ;(rest, end) <- interpretStatement body next
     ;addBlock label rest end
     ;return ([], Branch label)
 
 
 
 };interpretStatement stmt@(CCase expr body node) next = do{
    selector <- getSwitchExpression stmt
     ;let{ condition = CBinary CEqOp selector expr node
      ;addSwitchCase (Just condition) body next
  }};interpretStatement stmt@(CCases lower upper body node) next = do{
    selector <- getSwitchExpression stmt
     ;let{ condition = CBinary CLndOp
              (CBinary CGeqOp selector lower node)
              (CBinary CLeqOp selector upper node)
              node
      ;addSwitchCase (Just condition) body next
  }};interpretStatement (CDefault body _) next =
    addSwitchCase Nothing body next



;interpretStatement (CExpr Nothing _) next = next



;interpretStatement (CExpr (Just expr) _) next = do{
    expr' <- lift $ lift $ interpretExpr False expr
     ;(rest, end) <- next
     ;return (resultToStatements expr' ++ rest, end)
 
 
 
 };interpretStatement (CCompound [] items _) next = mapBuildCFGT (mapRWST scope) $ do{
    foldr interpretBlockItem next items
 
 
 
 };interpretStatement (CIf c t mf _) next = do{
    c' <- lift $ lift $ interpretExpr True c
     ;after <- newLabel
 
     ;falseLabel <- case mf of{
         Nothing -> return after
          ;Just f -> do{
              (falseEntry, falseTerm) <- interpretStatement f (return ([], Branch after))
               ;falseLabel <- newLabel
               ;addBlock falseLabel falseEntry falseTerm
               ;return falseLabel
   
       }};(trueEntry, trueTerm) <- interpretStatement t (return ([], Branch after))
     ;trueLabel <- newLabel
     ;addBlock trueLabel trueEntry trueTerm
 
     ;(rest, end) <- next
     ;addBlock after rest end
 
     ;return ([], CondBranch c' trueLabel falseLabel)
 
 
 
 };interpretStatement stmt@(CSwitch expr body node) next = do{
    (bindings, expr') <- case expr of{
         CVar{} -> return ([], expr)
          ;_ -> lift $ lift $ do{
              ident <- fmap internalIdent (uniqueName "c3dpdGNo")
               ;rhs <- interpretExpr True expr
               ;var <- addSymbolIdent ident (Rust.Immutable, resultType rhs)
               ;return
                   ( [Rust.Let Rust.Immutable (Rust.VarName var) Nothing (Just (result rhs))]
                   , CVar ident node
                   )
   
       }};after <- newLabel
     ;(_, SwitchCases cases) <- getSwitchCases expr' $ setBreak after $
         interpretStatement body (return ([], Branch after))
 
     ;let{ (conditions, defaults) = IntMap.mapEither isDefault cases
      ;defaultCase <- case IntMap.keys defaults of{
          [] -> return after
           ;[defaultCase] -> return defaultCase
           ;_ -> lift $ lift $ badSource stmt "ZHVwbGljYXRlIGRlZmF1bHQgY2FzZXM="
   
       };entry <- foldrM conditionBlock defaultCase (IntMap.toList conditions)
  
      ;(rest, end) <- next
      ;addBlock after rest end
  
      ;return (bindings, Branch entry)
      ;where{
      conditionBlock (target, condition) defaultCase = do{
           label <- newLabel
            ;addBlock label [] (CondBranch condition target defaultCase)
            ;return label
    
    
    
    }}}};interpretStatement (CWhile c body doWhile _) next = do{
    c' <- lift $ lift $ interpretExpr True c
     ;after <- newLabel
 
     ;headerLabel <- newLabel
     ;(bodyEntry, bodyTerm) <- setBreak after $ setContinue headerLabel $
         interpretStatement body (return ([], Branch headerLabel))
 
     ;bodyLabel <- newLabel
     ;addBlock bodyLabel bodyEntry bodyTerm
 
     ;addBlock headerLabel [] $ case toBool c' of{
         Rust.Lit (Rust.LitBool cont) | cont /= doWhile ->
              Branch (if cont then bodyLabel else after)
          ;_ -> CondBranch c' bodyLabel after
  
      };(rest, end) <- next
     ;addBlock after rest end
 
     ;return ([], Branch (if doWhile then bodyLabel else headerLabel))
 
 
 
 };interpretStatement (CFor initial mcond mincr body _) next = do{
    after <- newLabel
 
     ;ret <- mapBuildCFGT (mapRWST scope) $ do{
         prefix <- case initial of{
              Left Nothing -> return []
               ;Left (Just expr) -> do{
                   expr' <- lift $ lift $ interpretExpr False expr
                    ;return (resultToStatements expr')
                };Right decls -> lift $ lift $ interpretDeclarations makeLetBinding decls
   
           };headerLabel <- newLabel
          ;incrLabel <- case mincr of{
              Nothing -> return headerLabel
               ;Just incr -> do{
                   incr' <- lift $ lift $ interpretExpr False incr
                    ;incrLabel <- newLabel
                    ;addBlock incrLabel (resultToStatements incr') (Branch headerLabel)
                    ;return incrLabel
    
            }};(bodyEntry, bodyTerm) <- setBreak after $ setContinue incrLabel $
              interpretStatement body (return ([], Branch incrLabel))
  
          ;bodyLabel <- newLabel
          ;addBlock bodyLabel bodyEntry bodyTerm
  
          ;cond <- case mcond of{
              Just cond -> do{
                   cond' <- lift $ lift $ interpretExpr True cond
                    ;return (CondBranch cond' bodyLabel after)
                };Nothing -> return (Branch bodyLabel)
           };addBlock headerLabel [] cond
  
          ;return (prefix, Branch headerLabel)
  
      };(rest, end) <- next
     ;addBlock after rest end
 
     ;return ret
 
 
 
 };interpretStatement (CGoto ident _) next = do{
    _ <- next
     ;label <- gotoLabel ident
     ;return ([], Branch label)
 
 
 
 };interpretStatement stmt@(CCont _) next = do{
    _ <- next
     ;val <- lift (asks onContinue)
     ;case val of{
         Just label -> return ([], Branch label)
          ;Nothing -> lift $ lift $ badSource stmt "Y29udGludWUgb3V0c2lkZSBsb29w"
  }};interpretStatement stmt@(CBreak _) next = do{
    _ <- next
     ;val <- lift (asks onBreak)
     ;case val of{
         Just label -> return ([], Branch label)
          ;Nothing -> lift $ lift $ badSource stmt "YnJlYWsgb3V0c2lkZSBsb29w"
  
  
  
  }};interpretStatement stmt@(CReturn expr _) next = do{
    _ <- next
     ;lift $ lift $ do{
         val <- lift (asks functionReturnType)
          ;case val of{
              Nothing -> badSource stmt "cmV0dXJuIHN0YXRlbWVudCBvdXRzaWRlIGZ1bmN0aW9u"
               ;Just retTy -> do{
                   expr' <- mapM (fmap (castTo retTy) . interpretExpr True) expr
                    ;return (exprToStatements (Rust.Return expr'), Unreachable)
    
    
    
    }}}};interpretStatement stmt _ = lift $ lift $ unimplemented stmt



;setBreak :: Label -> CSourceBuildCFGT s a -> CSourceBuildCFGT s a
;setBreak label =
    mapBuildCFGT (local (\ flow -> flow { onBreak = Just label }))

;setContinue :: Label -> CSourceBuildCFGT s a -> CSourceBuildCFGT s a
;setContinue label =
    mapBuildCFGT (local (\ flow -> flow { onContinue = Just label }))



;getSwitchExpression :: CStat -> CSourceBuildCFGT s CExpr
;getSwitchExpression stmt = do{
    mexpr <- lift $ asks switchExpression
     ;case mexpr of{
         Nothing -> lift $ lift $ badSource stmt "Y2FzZSBvdXRzaWRlIHN3aXRjaA=="
          ;Just expr -> return expr
  
  }};addSwitchCase :: Maybe CExpr -> CStat -> CSourceBuildCFGT s ([Rust.Stmt], Terminator Result) -> CSourceBuildCFGT s ([Rust.Stmt], Terminator Result)
;addSwitchCase condition body next = do{
    condition' <- lift $ lift $ mapM (interpretExpr True) condition
     ;next' <- interpretStatement body next
     ;label <- case next' of{
         ([], Branch to) -> return to
          ;(rest, end) -> do{
              label <- newLabel
               ;addBlock label rest end
               ;return label
       }};lift $ tell $ SwitchCases $ IntMap.singleton label condition'
     ;return ([], Branch label)
 
 };getSwitchCases :: CExpr -> CSourceBuildCFGT s a -> CSourceBuildCFGT s (a, SwitchCases)
;getSwitchCases expr = mapBuildCFGT wrap
    where{
    wrap body = do{
         ((a, st), cases) <- censor (const mempty)
              $ local (\ flow -> flow { switchExpression = Just expr })
              $ listen body
          ;return ((a, cases), st)
  
  
  
  }};gotoLabel :: Ident -> CSourceBuildCFGT s Label
;gotoLabel ident = do{
    labels <- lift get
     ;case Map.lookup ident labels of{
         Nothing -> do{
              label <- newLabel
               ;lift (put (Map.insert ident label labels))
               ;return label
           };Just label -> return label
  
  
  
  }};cfgToRust :: (Pretty node, Pos node) => node -> CSourceBuildCFGT s ([Rust.Stmt], Terminator Result) -> EnvMonad s [Rust.Stmt]
;cfgToRust _node build = do{
    let{ builder = buildCFG $ do{
              (early, term) <- build
               ;entry <- newLabel
               ;addBlock entry early term
               ;return entry
       };(rawCFG, _) <- evalRWST builder (OuterLabels Nothing Nothing Nothing) Map.empty
  
  
  
      ;let{ cfg = depthFirstOrder (removeEmptyBlocks rawCFG)
       ;let{ (hasGoto, structured) = structureCFG mkBreak mkContinue mkLoop mkIf mkGoto mkMatch cfg
        ;return $ if hasGoto then declCurrent : structured else structured
        ;where{
    
    
    
        loopLabel l = Rust.Lifetime ("bG9vcA==" ++ show l)
         ;mkBreak l = exprToStatements (Rust.Break (fmap loopLabel l))
         ;mkContinue l = exprToStatements (Rust.Continue (fmap loopLabel l))
         ;mkLoop l b = exprToStatements (Rust.Loop (Just (loopLabel l)) (statementsToBlock b))
         ;mkIf c t f = exprToStatements (simplifyIf c (statementsToBlock t) (statementsToBlock f))
     
         ;currentBlock = Rust.VarName "X2N1cnJlbnRCbG9jaw=="
         ;declCurrent = Rust.Let Rust.Mutable currentBlock Nothing Nothing
         ;mkGoto l = exprToStatements (Rust.Assign (Rust.Var currentBlock) (Rust.K) (fromIntegral l))
         ;mkMatch = flip (foldr go)
             where{
             go (l, t) f = exprToStatements (Rust.IfThenElse (Rust.CmpEQ (Rust.Var currentBlock) (fromIntegral l)) (statementsToBlock t) (statementsToBlock f))
      
      
      
              ;simplifyIf c (Rust.Block [] Nothing) (Rust.Block [] Nothing) =
                  result c
          
      
      
              ;simplifyIf c (Rust.Block [] Nothing) f =
                  Rust.IfThenElse (toNotBool c) f (Rust.Block [] Nothing)
          
      
      
              ;simplifyIf c t f = Rust.IfThenElse (toBool c) t f
          
      
      
      }}}}}};interpretBlockItem :: CBlockItem -> CSourceBuildCFGT s ([Rust.Stmt], Terminator Result) -> CSourceBuildCFGT s ([Rust.Stmt], Terminator Result)
;interpretBlockItem (CBlockStmt stmt) next = interpretStatement stmt next
;interpretBlockItem (CBlockDecl decl) next = do{
    decl' <- lift $ lift (interpretDeclarations makeLetBinding decl)
     ;(rest, end) <- next
     ;return (decl' ++ rest, end)
 };interpretBlockItem item _ = lift $ lift (unimplemented item)



;scope :: EnvMonad s a -> EnvMonad s a
;scope m = do{
    
    old <- lift get
     ;a <- m
     
     ;lift (modify (\ st -> old { globalState = globalState st }))
     ;return a
 
 
 
 };blockToStatements :: Rust.Block -> [Rust.Stmt]
;blockToStatements (Rust.Block stmts mexpr) = case mexpr of{
    Just expr -> stmts ++ exprToStatements expr
     ;Nothing -> stmts
 
 
 
 };statementsToBlock :: [Rust.Stmt] -> Rust.Block
;statementsToBlock [Rust.Stmt (Rust.BlockExpr stmts)] = stmts
;statementsToBlock stmts = Rust.Block stmts Nothing



;exprToStatements :: Rust.Expr -> [Rust.Stmt]
;exprToStatements (Rust.IfThenElse c t f) =
    [Rust.Stmt (Rust.IfThenElse c (extractExpr t) (extractExpr f))]
    where{
    extractExpr = statementsToBlock . blockToStatements
 };exprToStatements (Rust.BlockExpr b) = blockToStatements b
;exprToStatements e = [Rust.Stmt e]



;data Result = Result
    { resultType :: CType
    , resultMutable :: Rust.Mutable
    , result :: Rust.Expr
    }



;resultToStatements :: Result -> [Rust.Stmt]
;resultToStatements = exprToStatements . result



;typeToResult :: IntermediateType -> Rust.Expr -> Result
;typeToResult itype expr = Result
    { resultType = typeRep itype
    , resultMutable = typeMutable itype
    , result = expr
    }



;interpretExpr :: Bool -> CExpr -> EnvMonad s Result



;interpretExpr demand (CComma exprs _) = do{
    let{ (effects, mfinal) = if demand then (init exprs, Just (last exprs)) else (exprs, Nothing)
      ;effects' <- mapM (fmap resultToStatements . interpretExpr False) effects
      ;mfinal' <- mapM (interpretExpr True) mfinal
      ;return Result
          { resultType = maybe IsVoid resultType mfinal'
          , resultMutable = maybe Rust.Immutable resultMutable mfinal'
          , result = Rust.BlockExpr (Rust.Block (concat effects') (fmap result mfinal'))
          }
  
  
  
  }};interpretExpr demand expr@(CAssign op lhs rhs _) = do{
    lhs' <- interpretExpr True lhs
     ;rhs' <- interpretExpr True rhs
     ;compound expr False demand op lhs' rhs'
 
 
 
 };interpretExpr demand expr@(CCond c (Just t) f _) = do{
    c' <- fmap toBool (interpretExpr True c)
     ;t' <- interpretExpr demand t
     ;f' <- interpretExpr demand f
     ;if demand
         then promotePtr expr (mkIf c') t' f'
         else return Result
             { resultType = IsVoid
             , resultMutable = Rust.Immutable
             , result = mkIf c' (result t') (result f')
             }
     ;where{
     mkIf c' t' f' = Rust.IfThenElse c' (Rust.Block [] (Just t')) (Rust.Block [] (Just f'))
  
  
  
  }};interpretExpr _ expr@(CBinary op lhs rhs _) = do{
    lhs' <- interpretExpr True lhs
     ;rhs' <- interpretExpr True rhs
     ;binop expr op lhs' rhs'
 
 
 
 };interpretExpr _ (CCast decl expr _) = do{
    (_mut, ty) <- typeName decl
     ;expr' <- interpretExpr (ty /= IsVoid) expr
     ;return Result
         { resultType = ty
         , resultMutable = Rust.Immutable
         , result = (if ty == IsVoid then result else castTo ty) expr'
         }
 
 
 
 };interpretExpr demand node@(CUnary op expr _) = case op of{
    CPreIncOp -> incdec False CAddAssOp
     ;CPreDecOp -> incdec False CSubAssOp
     ;CPostIncOp -> incdec True CAddAssOp
     ;CPostDecOp -> incdec True CSubAssOp
 
 
 
     ;CAdrOp -> do{
         expr' <- interpretExpr True expr
          ;let{ ty' = IsPtr (resultMutable expr') (resultType expr')
           ;return Result
               { resultType = ty'
               , resultMutable = Rust.Immutable
               , result = Rust.Cast (Rust.Borrow (resultMutable expr') (result expr')) (toRustType ty')
               }
   
   
   
       }};CIndOp -> do{
         expr' <- interpretExpr True expr
          ;case resultType expr' of{
              IsPtr mut' ty' -> return Result
                   { resultType = ty'
                   , resultMutable = mut'
                   , result = Rust.Deref (result expr')
                   }
               ;IsFunc{} -> return expr'
               ;_ -> badSource node "ZGVyZWZlcmVuY2Ugb2Ygbm9uLXBvaW50ZXI="
   
   
   
       }};CPlusOp -> do{
         expr' <- interpretExpr demand expr
          ;let{ ty' = intPromote (resultType expr')
           ;return Result
               { resultType = ty'
               , resultMutable = Rust.Immutable
               , result = castTo ty' expr'
               }
   
   
   
       }};CMinOp -> fmap wrapping $ simple Rust.Neg
 
 
 
     ;CCompOp -> simple Rust.Not
 
 
 
     ;CNegOp -> do{
         expr' <- interpretExpr True expr
          ;return Result
              { resultType = IsBool
              , resultMutable = Rust.Immutable
              , result = toNotBool expr'
              }
  
  
  
      };where{
     incdec returnOld assignop = do{
          expr' <- interpretExpr True expr
           ;compound node returnOld demand assignop expr' Result
               { resultType = IsInt Signed (BitWidth 32)
               , resultMutable = Rust.Immutable
               , result = 1
               }
       };simple f = do{
          expr' <- interpretExpr True expr
           ;let{ ty' = intPromote (resultType expr')
            ;return Result
                { resultType = ty'
                , resultMutable = Rust.Immutable
                , result = f (castTo ty' expr')
                }
    
    
    
    }}}};interpretExpr _ (CSizeofExpr e _) = do{
    e' <- interpretExpr True e
     ;return (rustSizeOfType (toRustType (resultType e')))
 };interpretExpr _ (CSizeofType decl _) = do{
    (_mut, ty) <- typeName decl
     ;return (rustSizeOfType (toRustType ty))
 };interpretExpr _ (CAlignofExpr e _) = do{
    e' <- interpretExpr True e
     ;return (rustAlignOfType (toRustType (resultType e')))
 };interpretExpr _ (CAlignofType decl _) = do{
    (_mut, ty) <- typeName decl
     ;return (rustAlignOfType (toRustType ty))
 
 
 
 };interpretExpr _ expr@(CIndex lhs rhs _) = do{
    lhs' <- interpretExpr True lhs
     ;rhs' <- interpretExpr True rhs
     ;case (resultType lhs', resultType rhs') of{
         (IsArray mut _ el, _) -> return (subscript mut el (result lhs') rhs')
          ;(_, IsArray mut _ el) -> return (subscript mut el (result rhs') lhs')
          ;_ -> do{
              ptr <- binop expr CAddOp lhs' rhs'
               ;case resultType ptr of{
                   IsPtr mut ty -> return Result
                        { resultType = ty
                        , resultMutable = mut
                        , result = Rust.Deref (result ptr)
                        }
                    ;_ -> badSource expr "YXJyYXkgc3Vic2NyaXB0IG9mIG5vbi1wb2ludGVy"
        }}};where{
     subscript mut el arr idx = Result
          { resultType = el
          , resultMutable = mut
          , result = Rust.Index arr (castTo (IsInt Unsigned WordWidth) idx)
          }
  
  
  
  }};interpretExpr _ expr@(CCall func args _) = do{
    func' <- interpretExpr True func
     ;case resultType func' of{
         IsFunc retTy argTys variadic -> do{
              args' <- castArgs variadic (map snd argTys) args
               ;return Result
                   { resultType = retTy
                   , resultMutable = Rust.Immutable
                   , result = Rust.Call (result func') args'
                   }
           };_ -> badSource expr "ZnVuY3Rpb24gY2FsbCB0byBub24tZnVuY3Rpb24="
      };where{
 
 
 
     castArgs _ [] [] = return []
      ;castArgs variadic (ty : tys) (arg : rest) = do{
          arg' <- interpretExpr True arg
           ;args' <- castArgs variadic tys rest
           ;return (castTo ty arg' : args')
       };castArgs True [] rest = mapM (fmap promoteArg . interpretExpr True) rest
      ;castArgs False [] _ = badSource expr "YXJndW1lbnRzICh0b28gbWFueSk="
      ;castArgs _ _ [] = badSource expr "YXJndW1lbnRzICh0b28gZmV3KQ=="
  
  
  
      ;promoteArg :: Result -> Rust.Expr
      ;promoteArg r = case resultType r of{
          IsFloat _ -> castTo (IsFloat 64) r
           ;IsArray mut _ el -> castTo (IsPtr mut el) r
           ;ty -> castTo (intPromote ty) r
   
   
   
   }}};interpretExpr _ expr@(CMember obj ident deref node) = do{
    obj' <- interpretExpr True $ if deref then CUnary CIndOp obj node else obj
     ;objTy <- completeType (resultType obj')
     ;fields <- case objTy of{
         IsStruct _ fields -> return fields
          ;_ -> badSource expr "bWVtYmVyIGFjY2VzcyBvZiBub24tc3RydWN0"
      };let{ field = applyRenames ident
      ;ty <- case lookup field fields of{
          Just ty -> return ty
           ;Nothing -> badSource expr "cmVxdWVzdCBmb3Igbm9uLWV4aXN0ZW50IGZpZWxk"
       };return Result
          { resultType = ty
          , resultMutable = resultMutable obj'
          , result = Rust.Member (result obj') (Rust.VarName field)
          }
  
  
  
  }};interpretExpr _ expr@(CVar ident _) = do{
    sym <- getSymbolIdent ident
     ;maybe (badSource expr "dW5kZWZpbmVkIHZhcmlhYmxl") return sym
 
 
 
 };interpretExpr _ expr@(CConst c) = case c of{



    CIntConst (CInteger v repr flags) _ ->
         let{
             allow_signed = not (testFlag FlagUnsigned flags)
              ;widths =
                  [ (32 :: Int,
                      if any (`testFlag` flags) [FlagLongLong, FlagLong]
                      then WordWidth else BitWidth 32)
                  , (64, BitWidth 64)
                  ]
              ;allowed_types =
                  [ IsInt s w
                  | (bits, w) <- widths
                  , (True, s) <- [(allow_signed, Signed), (allow_unsigned, Unsigned)]
                  , v < 2 ^ (bits - if s == Signed then 1 else 0)
                  ]
              ;repr' = case repr of{
                  DecRepr -> Rust.DecRepr
                   ;OctalRepr -> Rust.OctalRepr
                   ;HexRepr -> Rust.HexRepr
           }}in case allowed_types of{
         [] -> badSource expr "aW50ZWdlciAodG9vIGJpZyk="
          ;ty : _ -> return (literalNumber ty (Rust.LitInt v repr'))
      };CFloatConst (CFloat str) _ -> case span (`notElem` "ZkY=") str of{
         (v, "") -> return (literalNumber (IsFloat 64) (Rust.LitFloat v))
          ;(v, [_]) -> return (literalNumber (IsFloat 32) (Rust.LitFloat v))
          ;_ -> badSource expr "ZmxvYXQ="
  
  
  
      };CCharConst (CChar ch False) _ -> return Result
         { resultType = charType
         , resultMutable = Rust.Immutable
         , result = Rust.Lit (Rust.LitByteChar ch)
         }
 
 
 
     ;CStrConst (CString str False) _ -> return Result
         { resultType = IsArray Rust.Immutable (length str + 1) charType
         , resultMutable = Rust.Immutable
         , result = Rust.Deref (Rust.Lit (Rust.LitByteStr (str ++ "MA==")))
         }
     ;_ -> unimplemented expr
     ;where{
 
 
 
     literalNumber ty lit = Result
          { resultType = ty
          , resultMutable = Rust.Immutable
          , result = Rust.Lit (lit (toRustType ty))
          }
  
  
  
  }};interpretExpr _ (CCompoundLit decl initials info) = do{
    (mut, ty) <- typeName decl
     ;final <- interpretInitializer ty (CInitList initials info)
     ;return Result
         { resultType = ty
         , resultMutable = mut
         , result = final
         }
 
 
 
 };interpretExpr demand stat@(CStatExpr (CCompound [] stmts _) _) = scope $ do{
    let{ (effects, final) = case last stmts of{
              CBlockStmt (CExpr expr _) | demand -> (init stmts, expr)
               ;_ -> (stmts, Nothing)
       };effects' <- cfgToRust stat (foldr interpretBlockItem (return ([], Unreachable)) effects)
      ;final' <- mapM (interpretExpr True) final
      ;return Result
          { resultType = maybe IsVoid resultType final'
          , resultMutable = maybe Rust.Immutable resultMutable final'
          , result = Rust.BlockExpr (Rust.Block effects' (fmap result final'))
          }
  
  
  
  }};interpretExpr _ expr = unimplemented expr



;wrapping :: Result -> Result
;wrapping r = r

;toPtr :: Result -> Maybe Result
;toPtr _ = Nothing

;binop :: CExpr -> CBinaryOp -> Result -> Result -> EnvMonad s Result
;binop expr op lhs rhs = fmap wrapping $ case op of{
    CMulOp -> promote expr Rust.Mul lhs rhs
     ;CDivOp -> promote expr Rust.Div lhs rhs
     ;CRmdOp -> promote expr Rust.Mod lhs rhs
     ;CAddOp -> case (toPtr lhs, toPtr rhs) of{
         (Just ptr, _) -> return (offset ptr rhs)
          ;(_, Just ptr) -> return (offset ptr lhs)
          ;_ -> promote expr Rust.Add lhs rhs
          ;where{
          offset ptr idx = ptr
               { result = Rust.MethodCall (result ptr) (Rust.VarName "b2Zmc2V0") [castTo (IsInt Signed WordWidth) idx]
               }
       }};CSubOp -> case (toPtr lhs, toPtr rhs) of{
         (Just lhs', Just rhs') -> do{
              ptrTo <- case compatiblePtr (resultType lhs') (resultType rhs') of{
                   IsPtr _ ptrTo -> return ptrTo
                    ;_ -> badSource expr "cG9pbnRlciBzdWJ0cmFjdGlvbiBvZiBpbmNvbXBhdGlibGUgcG9pbnRlcnM="
                };let{ ty = IsInt Signed WordWidth
                ;let{ size = rustSizeOfType (toRustType ptrTo)
                 ;return Result
                     { resultType = ty
                     , resultMutable = Rust.Immutable
                     , result = (Rust.MethodCall (castTo ty lhs') (Rust.VarName "d3JhcHBpbmdfc3Vi") [castTo ty rhs']) castTo ty size
                     }
             }}};(Just ptr, _) -> return ptr { result = Rust.MethodCall (result ptr) (Rust.VarName "b2Zmc2V0") [Rust.Neg (castTo (IsInt Signed WordWidth) rhs)] }
          ;_ -> promote expr Rust.Sub lhs rhs
      };CShlOp -> shift Rust.ShiftL
     ;CShrOp -> shift Rust.ShiftR
     ;CLeOp -> comparison Rust.CmpLT
     ;CGrOp -> comparison Rust.CmpGT
     ;CLeqOp -> comparison Rust.CmpLE
     ;CGeqOp -> comparison Rust.CmpGE
     ;CEqOp -> comparison Rust.CmpEQ
     ;CNeqOp -> comparison Rust.CmpNE
     ;CAndOp -> promote expr Rust.And lhs rhs
     ;CXorOp -> promote expr Rust.Xor lhs rhs
     ;COrOp -> promote expr Rust.Or lhs rhs
     ;CLndOp -> return Result { resultType = IsBool, resultMutable = Rust.Immutable, result = Rust.LAnd (toBool lhs) (toBool rhs) }
     ;CLorOp -> return Result { resultType = IsBool, resultMutable = Rust.Immutable, result = Rust.LOr (toBool lhs) (toBool rhs) }
     ;where{
     shift op' = return Result
          { resultType = lhsTy
          , resultMutable = Rust.Immutable
          , result = op' (castTo lhsTy lhs) (castTo rhsTy rhs)
          }
          where{
          lhsTy = intPromote (resultType lhs)
           ;rhsTy = intPromote (resultType rhs)
       };comparison op' = do{
          res <- promotePtr expr op' lhs rhs
           ;return res { resultType = IsBool }
   
   
   
   }}};compound :: CExpr -> Bool -> Bool -> CAssignOp -> Result -> Result -> EnvMonad s Result
;compound expr returnOld demand op lhs rhs = do{
    let{ op' = case op of{
              CAssignOp -> Nothing
               ;CMulAssOp -> Just CMulOp
               ;CDivAssOp -> Just CDivOp
               ;CRmdAssOp -> Just CRmdOp
               ;CAddAssOp -> Just CAddOp
               ;CSubAssOp -> Just CSubOp
               ;CShlAssOp -> Just CShlOp
               ;CShrAssOp -> Just CShrOp
               ;CAndAssOp -> Just CAndOp
               ;CXorAssOp -> Just CXorOp
               ;COrAssOp  -> Just COrOp
   
   
   
       };let{ duplicateLHS = isJust op' || demand
   
   
   
       ;let{ (bindings1, dereflhs, boundrhs) =
                if not duplicateLHS || hasNoSideEffects (result lhs)
                then ([], lhs, rhs)
                else
                    let{ lhsvar = Rust.VarName "X2xocw=="
                     ;in ([ Rust.Let Rust.Immutable rhsvar Nothing (Just (result rhs))
                         , Rust.Let Rust.Immutable lhsvar Nothing (Just (Rust.Borrow Rust.Mutable (result lhs)))
                         ], lhs { result = Rust.Deref (Rust.Var lhsvar) }, rhs { result = Rust.Var rhsvar })
         };rhs' <- case op' of{
            Just o -> binop expr o dereflhs boundrhs
             ;Nothing -> return boundrhs
         };let{ assignment = Rust.Assign (result dereflhs) (Rust.K) (castTo (resultType lhs) rhs')
     
     
     
         ;let{ (bindings2, ret) =
                  if not demand
                  then ([], Nothing)
                  else if not returnOld
                  then ([], Just (result dereflhs))
                  else
                      let{ oldvar = Rust.VarName "X29sZA=="
                       ;in ([Rust.Let Rust.Immutable oldvar Nothing (Just (result dereflhs))], Just (Rust.Var oldvar))
       
       
       
           };return $ case Rust.Block (bindings1 ++ bindings2 ++ exprToStatements assignment) ret of{
              b@(Rust.Block body Nothing) -> Result
                   { resultType = IsVoid
                   , resultMutable = Rust.Immutable
                   , result = case body of{
                       [Rust.Stmt e] -> e
                        ;_ -> Rust.BlockExpr b
                    }}
               ;b -> lhs { result = Rust.BlockExpr b }
           };where{
      
      
      
          hasNoSideEffects (Rust.Var{}) = True
           ;hasNoSideEffects (Rust.Path{}) = True
           ;hasNoSideEffects (Rust.Member e _) = hasNoSideEffects e
           ;hasNoSideEffects (Rust.Deref p) = hasNoSideEffects p
           ;hasNoSideEffects _ = False
       
       
       
       }}}}}}};rustSizeOfType :: Rust.Type -> Result
;rustSizeOfType (Rust.TypeName ty) = Result
        { resultType = IsInt Unsigned WordWidth
        , resultMutable = Rust.Immutable
        , result = Rust.Call (Rust.Var (Rust.VarName ("OjpzdGQ6Om1lbTo6c2l6ZV9vZjo6PA==" ++ ty ++ "Pg=="))) []
        }

;rustAlignOfType :: Rust.Type -> Result
;rustAlignOfType (Rust.TypeName ty) = Result
        { resultType = IsInt Unsigned WordWidth
        , resultMutable = Rust.Immutable
        , result = Rust.Call (Rust.Var (Rust.VarName ("OjpzdGQ6Om1lbTo6YWxpZ25fb2Y6Ojw=" ++ ty ++ "Pg=="))) []
        }



;interpretConstExpr :: CExpr -> EnvMonad s Integer
;interpretConstExpr (CConst (CIntConst (CInteger v _ _) _)) = return v
;interpretConstExpr expr = unimplemented expr



;castTo :: CType -> Result -> Rust.Expr
;castTo target source | resultType source == target = result source



;castTo IsBool source = toBool source



;castTo target source = Rust.Cast (result source) (toRustType target)



;toBool :: Result -> Rust.Expr






    IsBool -> v



    IsPtr _ _ -> Rust.Not (Rust.MethodCall v (Rust.VarName "aXNfbnVsbA==") [])



    _ -> Rust.CmpNE v 0



;intPromote :: CType -> CType



;intPromote IsBool = IsInt Signed (BitWidth 32)
;intPromote (IsEnum _) = enumReprType
;intPromote (IsInt _ (BitWidth w)) | w < 32 = IsInt Signed (BitWidth 32)



;intPromote x = x



;usual :: CType -> CType -> Maybe CType
;usual (IsFloat aw) (IsFloat bw) = Just (IsFloat (max aw bw))
;usual a@(IsFloat _) _ = Just a
;usual _ b@(IsFloat _) = Just b



;usual origA origB = case (intPromote origA, intPromote origB) of{



        (a, b) | a == b -> Just a
     
 
 
         ;(IsInt Signed sw, IsInt Unsigned uw) -> mixedSign sw uw
         ;(IsInt Unsigned uw, IsInt Signed sw) -> mixedSign sw uw
         ;(IsInt as aw, IsInt _bs bw) -> do{
             rank <- integerConversionRank aw bw
              ;Just (IsInt as (if rank == GT then aw else bw))
          };_ -> Nothing
         ;where{
     
 
 
         mixedSign sw uw = do{
              rank <- integerConversionRank uw sw
               ;Just $ case rank of{
                   GT -> IsInt Unsigned uw
                    ;EQ -> IsInt Unsigned uw
        
    
    
                    ;_ | bitWidth 64 uw < bitWidth 32 sw -> IsInt Signed sw
        
    
    
                    ;_ -> IsInt Unsigned sw
        
    
    
    }}}};integerConversionRank :: IntWidth -> IntWidth -> Maybe Ordering
;integerConversionRank (BitWidth a) (BitWidth b) = Just (compare a b)
;integerConversionRank WordWidth WordWidth = Just EQ
;integerConversionRank (BitWidth a) WordWidth
    | a <= 32 = Just LT
    | a >= 64 = Just GT
;integerConversionRank WordWidth (BitWidth b)
    | b <= 32 = Just GT
    | b >= 64 = Just LT
;integerConversionRank _ _ = Nothing



;promote
    :: (Pretty node, Pos node)
    => node
    -> (Rust.Expr -> Rust.Expr -> Rust.Expr)
    -> Result -> Result -> EnvMonad s Result
;promote node op a b = case usual (resultType a) (resultType b) of{
    Just rt -> return Result
         { resultType = rt
         , resultMutable = Rust.Immutable
         , result = op (castTo rt a) (castTo rt b)
         }
     ;Nothing -> badSource node $ concat
         [ "YXJpdGhtZXRpYyBjb21iaW5hdGlvbiBmb3Ig"
         , show (resultType a)
         , "IGFuZCA="
         , show (resultType b)
         ]
 
 
 
 };compatiblePtr :: CType -> CType -> CType
;compatiblePtr (IsPtr _ IsVoid) b = b
;compatiblePtr (IsArray mut _ el) b = compatiblePtr (IsPtr mut el) b
;compatiblePtr a (IsPtr _ IsVoid) = a
;compatiblePtr a (IsArray mut _ el) = compatiblePtr a (IsPtr mut el)
;compatiblePtr (IsPtr m1 a) (IsPtr m2 b) = IsPtr (leastMutable m1 m2) (compatiblePtr a b)
    where{
    leastMutable Rust.Mutable Rust.Mutable = Rust.Mutable
     ;leastMutable _ _ = Rust.Immutable
 };compatiblePtr a b | a == b = a



;compatiblePtr _ _ = IsVoid



;promotePtr
    :: (Pretty node, Pos node)
    => node
    -> (Rust.Expr -> Rust.Expr -> Rust.Expr)
    -> Result -> Result -> EnvMonad s Result
;promotePtr node op a b = case (resultType a, resultType b) of{
    (IsArray _ _ _, _) -> ptrs
     ;(IsPtr _ _, _) -> ptrs
     ;(_, IsArray _ _ _) -> ptrs
     ;(_, IsPtr _ _) -> ptrs
     ;_ -> promote node op a b
     ;where{
     ptrOrVoid r = case resultType r of{
          t@(IsArray _ _ _) -> t
           ;t@(IsPtr _ _) -> t
           ;_ -> IsPtr Rust.Mutable IsVoid
       };ty = compatiblePtr (ptrOrVoid a) (ptrOrVoid b)
      ;ptrs = return Result
          { resultType = ty
          , resultMutable = Rust.Immutable
          , result = op (castTo ty a) (castTo ty b)
          }
  
  
  
  }};data Signed = Signed | Unsigned
    deriving (Show, Eq)

;data IntWidth = BitWidth Int | WordWidth
    deriving (Show, Eq)



;bitWidth :: Int -> IntWidth -> Int
;bitWidth wordWidth WordWidth = wordWidth
;bitWidth _ (BitWidth w) = w



;data CType
    = IsBool
    | IsInt Signed IntWidth
    | IsFloat Int
    | IsVoid
    | IsFunc CType [(Maybe (Rust.Mutable, Ident), CType)] Bool
    | IsPtr Rust.Mutable CType
    | IsArray Rust.Mutable Int CType
    | IsStruct String [(String, CType)]
    | IsEnum String
    | IsIncomplete Ident
    deriving Show



;instance Eq CType where{
    IsBool == IsBool = True
     ;IsInt as aw == IsInt bs bw = as == bs && aw == bw
     ;IsFloat aw == IsFloat bw = aw == bw
     ;IsVoid == IsVoid = True
     ;IsFunc aRetTy aFormals aVariadic == IsFunc bRetTy bFormals bVariadic =
         aRetTy == bRetTy && aVariadic == bVariadic &&
         map snd aFormals == map snd bFormals
     ;IsPtr aMut aTy == IsPtr bMut bTy = aMut == bMut && aTy == bTy
     ;IsArray aMut _ aTy == IsArray bMut _ bTy = aMut == bMut && aTy == bTy
     ;IsStruct aName aFields == IsStruct bName bFields =
         aName == bName && aFields == bFields
     ;IsEnum aName == IsEnum bName = aName == bName
     ;IsIncomplete aName == IsIncomplete bName = aName == bName
     ;_ == _ = False
 
 
 
 };toRustType :: CType -> Rust.Type
;toRustType IsBool = Rust.TypeName "Ym9vbA=="
;toRustType (IsFloat w) = Rust.TypeName ('0' : show w)
;toRustType IsVoid = Rust.TypeName "OjpzdGQ6Om9zOjpyYXc6OmNfdm9pZA=="
;toRustType (IsFunc retTy args variadic) = Rust.TypeName $ concat
    [ "dW5zYWZlIGV4dGVybiBmbig="
    , args'
    , "KQ=="
    , if retTy /= IsVoid then "IC0+IA==" ++ typename retTy else ""
    ]
    where{
    typename (toRustType -> Rust.TypeName t) = t
     ;args' = intercalate "LCA=" (
             map (typename . snd) args ++ if variadic then ["Li4u"] else []
         )
 };toRustType (IsPtr mut to) = let{ Rust.TypeName to' = toRustType to in Rust.TypeName (rustMut mut ++ to')
     }where{
    rustMut Rust.Mutable = "Km11dCA="
     ;rustMut Rust.Immutable = "KmNvbnN0IA=="
 };toRustType (IsArray _ size el) = Rust.TypeName ("Ww==" ++ typename el ++ "OyA=" ++ show size ++ "XQ==")
    where{
    typename (toRustType -> Rust.TypeName t) = t
 };toRustType (IsStruct name _fields) = Rust.TypeName name
;toRustType (IsEnum name) = Rust.TypeName name
;toRustType (IsIncomplete ident) = Rust.TypeName (identToString ident)



;toRustRetType :: CType -> Rust.Type
;toRustRetType IsVoid = Rust.TypeName "KCk="
;toRustRetType ty = toRustType ty



;charType :: CType
;charType = IsInt Unsigned (BitWidth 8)



;enumReprType :: CType
;enumReprType = IsInt Signed (BitWidth 32)



;data IntermediateType = IntermediateType
    { typeMutable :: Rust.Mutable
    , typeIsFunc :: Bool
    , typeRep :: CType
    }



;runOnce :: EnvMonad s a -> EnvMonad s (EnvMonad s a)
;runOnce action = do{
    cacheRef <- lift $ lift $ newSTRef (Left action)
     ;return $ do{
         cache <- lift $ lift $ readSTRef cacheRef
          ;case cache of{
              Left todo -> do{
                   lift $ lift $ writeSTRef cacheRef $ Left $
                        fail "aW50ZXJuYWwgZXJyb3I6IHJ1bk9uY2UgYWN0aW9uIGRlcGVuZHMgb24gaXRzZWxmLCBsZWFkaW5nIHRvIGFuIGluZmluaXRlIGxvb3A="
                    ;val <- todo
                    ;lift $ lift $ writeSTRef cacheRef (Right val)
                    ;return val
                };Right val -> return val
   
   
   
   }}};baseTypeOf :: [CDeclSpec] -> EnvMonad s (Maybe CStorageSpec, EnvMonad s IntermediateType)
;baseTypeOf specs = do{
    
    let{ (storage, _attributes, basequals, basespecs, _inlineNoReturn, _align) = partitionDeclSpecs specs
      ;mstorage <- case storage of{
          [] -> return Nothing
           ;[spec] -> return (Just spec)
           ;_ : excess : _ -> badSource excess "ZXh0cmEgc3RvcmFnZSBjbGFzcyBzcGVjaWZpZXI="
       };base <- typedef (mutable basequals) basespecs
      ;return (mstorage, base)
      ;where{
  
  
  
      typedef mut [spec@(CTypeDef ident _)] = do{
   
   
   
           (name, mty) <- getTypedefIdent ident
            ;case mty of{
                Just deferred | mut == Rust.Immutable ->
                     return (fmap (\ itype -> itype { typeMutable = Rust.Immutable }) deferred)
                 ;Just deferred -> return deferred
     
     
     
                 ;Nothing | name == "X19idWlsdGluX3ZhX2xpc3Q=" -> runOnce $ do{
                     ty <- emitIncomplete Type ident
                      ;return IntermediateType
                          { typeMutable = mut
                          , typeIsFunc = False
                          , typeRep = IsPtr Rust.Mutable ty
                          }
                  };Nothing -> badSource spec "dW5kZWZpbmVkIHR5cGU="
     
     
     
         }};typedef mut other = do{
           deferred <- singleSpec other
            ;return (fmap (simple mut) deferred)
    
        };simple mut ty = IntermediateType
           { typeMutable = mut
           , typeIsFunc = False
           , typeRep = ty
           }
   
   
   
       ;singleSpec [CVoidType _] = return (return IsVoid)
       ;singleSpec [CBoolType _] = return (return IsBool)
   
   
   
       ;singleSpec [CSUType (CStruct CStructTag (Just ident) Nothing _ _) _] = do{
           mty <- getTagIdent ident
            ;return $ fromMaybe (emitIncomplete Struct ident) mty
    
    
    
        };singleSpec [CSUType (CStruct CStructTag mident (Just declarations) _ _) _] = do{
           deferredFields <- fmap concat $ forM declarations $ \ declaration -> case declaration of{
              CStaticAssert {} -> return []
               ;CDecl spec decls _ -> do{
                 (storage, base) <- baseTypeOf spec
                  ;case storage of{
                      Just s -> badSource s "c3RvcmFnZSBjbGFzcyBzcGVjaWZpZXIgaW4gc3RydWN0"
                       ;Nothing -> return ()
                   };forM decls $ \ decl -> case decl of{
                      (Just declr@(CDeclr (Just field) _ _ _ _), Nothing, Nothing) -> do{
                           deferred <- derivedDeferredTypeOf base declr []
                            ;return (applyRenames field, deferred)
                        };(_, Nothing, Just _size) -> do{
                           return ("PGJpdGZpZWxkPg==", unimplemented declaration)
                        };_ -> badSource declaration "ZmllbGQgaW4gc3RydWN0"
       
       
       
               }}};deferred <- runOnce $ do{
    
    
    
                (shouldEmit, name) <- case mident of{
                     Just ident -> do{
                          rewrites <- lift (asks itemRewrites)
                           ;case Map.lookup (Struct, identToString ident) rewrites of{
                               Just renamed -> return (False, concatMap ("Ojo=" ++) renamed)
                                ;Nothing -> return (True, identToString ident)
                        }};Nothing -> do{
                          name <- uniqueName "U3RydWN0"
                           ;return (True, name)
       
       
       
                   }};fields <- forM deferredFields $ \ (fieldName, deferred) -> do{
                     itype <- deferred
                      ;return (fieldName, typeRep itype)
      
      
      
                  };let{ attrs = [Rust.Attribute "ZGVyaXZlKENvcHkp", Rust.Attribute "cmVwcihDKQ=="]
                  ;when shouldEmit $ emitItems
                      [ Rust.Item attrs Rust.Public (Rust.Struct name [ (field, toRustType fieldTy) | (field, fieldTy) <- fields ])
                      , Rust.Item [] Rust.Private (Rust.CloneImpl (Rust.TypeName name))
                      ]
                  ;return (IsStruct name fields)
      
      
      
              }};case mident of{
                Just ident -> addTagIdent ident deferred
                 ;Nothing -> return ()
             };return deferred
    
    
    
        };singleSpec [CSUType (CStruct CUnionTag mident _ _ _) node] = runOnce $ do{
           ident <- case mident of{
                Just ident -> return ident
                 ;Nothing -> do{
                     name <- uniqueName "VW5pb24="
                      ;return (internalIdentAt (posOfNode node) name)
              }};emitIncomplete Union ident
    
    
    
        };singleSpec [spec@(CEnumType (CEnum (Just ident) Nothing _ _) _)] = do{
           mty <- getTagIdent ident
            ;case mty of{
                Just ty -> return ty
                 ;Nothing -> badSource spec "dW5kZWZpbmVkIGVudW0="
     
     
     
         }};singleSpec [CEnumType (CEnum mident (Just items) _ _) _] = do{
           deferred <- runOnce $ do{
                (shouldEmit, name) <- case mident of{
                     Just ident -> do{
                          rewrites <- lift (asks itemRewrites)
                           ;case Map.lookup (Enum, identToString ident) rewrites of{
                               Just renamed -> return (False, concatMap ("Ojo=" ++) renamed)
                                ;Nothing -> return (True, identToString ident)
                        }};Nothing -> do{
                          name <- uniqueName "RW51bQ=="
                           ;return (True, name)
       
                   
                   
                   }};enums <- forM items $ \ (ident, mexpr) -> do{
                     let{ enumName = applyRenames ident
                       ;case mexpr of{
                           Nothing -> return (Rust.EnumeratorAuto enumName)
                            ;Just expr -> do{
                                expr' <- interpretExpr True expr
                                 ;return (Rust.EnumeratorExpr enumName (castTo enumReprType expr'))
         
         
         
                     }}}};let{ Rust.TypeName repr = toRustType enumReprType
                  ;let{ attrs = [ Rust.Attribute "ZGVyaXZlKENsb25lLCBDb3B5KQ=="
                               , Rust.Attribute (concat [ "cmVwcig=", repr, "KQ==" ])
                               ]
                   ;when shouldEmit $
                       emitItems [Rust.Item attrs Rust.Public (Rust.Enum name enums)]
                   ;return (IsEnum name)
       
               }}};forM_ items $ \ (ident, _mexpr) -> addSymbolIdentAction ident $ do{
                IsEnum name <- deferred
                 ;return Result
                     { resultType = IsEnum name
                     , resultMutable = Rust.Immutable
                     , result = Rust.Path (Rust.PathSegments [name, applyRenames ident])
                     }
     
             };case mident of{
                Just ident -> addTagIdent ident deferred
                 ;Nothing -> return ()
             };return deferred
    
    
    
        };singleSpec other = return (foldrM arithmetic (IsInt Signed (BitWidth 32)) other)
   
       ;arithmetic :: CTypeSpec -> CType -> EnvMonad s CType
       ;arithmetic (CSignedType _) (IsInt _ width) = return (IsInt Signed width)
       ;arithmetic (CUnsigType _) (IsInt _ width) = return (IsInt Unsigned width)
       ;arithmetic (CCharType _) _ = return charType
       ;arithmetic (CShortType _) (IsInt s _) = return (IsInt s (BitWidth 16))
       ;arithmetic (CIntType _) (IsInt s _) = return (IsInt s (BitWidth 32))
       ;arithmetic (CLongType _) (IsInt s _) = return (IsInt s WordWidth)
       ;arithmetic (CLongType _) (IsFloat w) = return (IsFloat w)
       ;arithmetic (CFloatType _) _ = return (IsFloat 32)
       ;arithmetic (CDoubleType _) _ = return (IsFloat 64)
       ;arithmetic spec _ = unimplemented spec
   
   
   
   }}};derivedTypeOf :: EnvMonad s IntermediateType -> CDeclr -> EnvMonad s IntermediateType
;derivedTypeOf deferred declr = join (derivedDeferredTypeOf deferred declr [])

;derivedDeferredTypeOf
    :: EnvMonad s IntermediateType
    -> CDeclr
    -> [CDecl]
    -> EnvMonad s (EnvMonad s IntermediateType)
;derivedDeferredTypeOf deferred declr@(CDeclr _ derived _ _ _) argtypes = do{
    derived' <- mapM derive derived
     ;return $ do{
         basetype <- deferred
          ;foldrM ($) basetype derived'
      };where{
 
 
 
     derive (CPtrDeclr quals _) = return $ \ itype ->
          if typeIsFunc itype
          then return itype { typeIsFunc = False }
          else return itype
              { typeMutable = mutable quals
              , typeRep = IsPtr (typeMutable itype) (typeRep itype)
              }
      ;derive (CArrDeclr quals arraySize _) = return $ \ itype ->
          if typeIsFunc itype
          then badSource declr "ZnVuY3Rpb24gYXMgYXJyYXkgZWxlbWVudCB0eXBl"
          else do{
              sizeExpr <- case arraySize of{
                   CArrSize _ sizeExpr -> return sizeExpr
                    ;CNoArrSize _ -> unimplemented declr
                };size <- interpretConstExpr sizeExpr
               ;return itype
                   { typeMutable = mutable quals
                   , typeRep = IsArray (typeMutable itype) (fromInteger size) (typeRep itype)
                   }
   
   
   
       };derive (CFunDeclr foo _ _) = do{
          let{ preAnsiArgs = Map.fromList
                    [ (argname, CDecl argspecs [(Just declr', Nothing, Nothing)] pos)
                    | CDecl argspecs declrs _ <- argtypes
                    , (Just declr'@(CDeclr (Just argname) _ _ _ pos), Nothing, Nothing) <- declrs
                    ]
            ;(args, variadic) <- case foo of{
                Right (args, variadic) -> return (args, variadic)
                 ;Left argnames -> do{
                     argdecls <- forM argnames $ \ argname ->
                          case Map.lookup argname preAnsiArgs of{
                          Nothing -> badSource declr ("dW5kZWNsYXJlZCBhcmd1bWVudCA=" ++ show (identToString argname))
                           ;Just arg -> return arg
                       };return (argdecls, False)
              }};args' <- sequence
                [ do{
                    (storage, base') <- baseTypeOf argspecs
                     ;case storage of{
                         Nothing -> return ()
                          ;Just (CRegister _) -> return ()
                          ;Just s -> badSource s "c3RvcmFnZSBjbGFzcyBzcGVjaWZpZXIgb24gYXJndW1lbnQ="
                      };(argname, argTy) <- case declr' of{
                         [] -> return (Nothing, base')
                          ;[(Just argdeclr@(CDeclr argname _ _ _ _), Nothing, Nothing)] -> do{
                              argTy <- derivedDeferredTypeOf base' argdeclr []
                               ;return (argname, argTy)
                           };_ -> badSource arg "ZnVuY3Rpb24gYXJndW1lbnQ="
                      };return $ do{
                         itype <- argTy
                          ;when (typeIsFunc itype) (badSource arg "ZnVuY3Rpb24gYXMgZnVuY3Rpb24gYXJndW1lbnQ=")
                          ;let{ ty = case typeRep itype of{
                                   IsArray mut _ el -> IsPtr mut el
                                    ;orig -> orig
                            };return (fmap ((,) (typeMutable itype)) argname, ty)
                   }}}| arg@(CDecl argspecs declr' _) <-
    
    
    
                    case args of{
                    [CDecl [CTypeSpec (CVoidType _)] [] _] -> []
                     ;_ -> args
                 }]
            ;return $ \ itype -> do{
                when (typeIsFunc itype) (badSource declr "ZnVuY3Rpb24gYXMgZnVuY3Rpb24gcmV0dXJuIHR5cGU=")
                 ;args'' <- sequence args'
                 ;return itype
                     { typeIsFunc = True
                     , typeRep = IsFunc (typeRep itype) args'' variadic
                     }
     
     
     
     }}}}};mutable :: [CTypeQualifier a] -> Rust.Mutable
;mutable quals = if any (\ q -> case q of{ CConstQual _ -> True; _ -> False) quals then Rust.Immutable else Rust.Mutable
 
 };typeName :: CDecl -> EnvMonad s (Rust.Mutable, CType)
;typeName decl@(CStaticAssert {}) = badSource decl "c3RhdGljIGFzc2VydCBpbiB0eXBlIG5hbWUg"
;typeName decl@(CDecl spec declarators _) = do{
    (storage, base) <- baseTypeOf spec
     ;case storage of{
         Just s -> badSource s "c3RvcmFnZSBjbGFzcyBzcGVjaWZpZXIgaW4gdHlwZSBuYW1l"
          ;Nothing -> return ()
      };itype <- case declarators of{
         [] -> base
          ;[(Just declr@(CDeclr Nothing _ _ _ _), Nothing, Nothing)] ->
              derivedTypeOf base declr
          ;_ -> badSource decl "dHlwZSBuYW1l"
      };when (typeIsFunc itype) (badSource decl "dXNlIG9mIGZ1bmN0aW9uIHR5cGU=")
     ;return (typeMutable itype, typeRep itype)
 }}