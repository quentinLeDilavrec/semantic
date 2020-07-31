{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
module Analysis.ImportGraph
( ImportGraph
, importGraph
) where

import           Analysis.Carrier.Env.Monovariant
import qualified Analysis.Carrier.Heap.Monovariant as A
import qualified Analysis.Effect.Domain as A
import           Analysis.File
import           Analysis.FlowInsensitive
import           Analysis.Functor.Named
import           Control.Algebra
import           Control.Applicative (Alternative (..))
import           Control.Carrier.Fail.WithLoc
import           Control.Carrier.Fresh.Strict
import           Control.Carrier.Reader
import           Control.Carrier.State.Strict
import           Control.Monad.Trans.Class
import           Data.Foldable (fold)
import           Data.Function (fix)
import qualified Data.Map as Map
import qualified Data.Set as Set
import           Data.Text (Text)
import           Data.Traversable (for)
import           Prelude hiding (fail)
import           Source.Span
import           Syntax.Scope (Scope)
import qualified System.Path as Path

type ImportGraph = Map.Map Text (Set.Set Text)

type Addr = Name

data Value semi = Value
  { valueSemi  :: semi
  , valueGraph :: ImportGraph
  }
  deriving (Eq, Ord, Show)

instance Semigroup (Value (Semi term)) where
  Value _ g1 <> Value _ g2 = Value Abstract (Map.unionWith (<>) g1 g2)

instance Monoid (Value (Semi term)) where
  mempty = Value Abstract mempty

data Semi term
  = Closure Path.AbsRelFile Span (Named (Scope () term Addr))
  -- FIXME: Bound String values.
  | String Text
  | Abstract

deriving instance ( forall a . Eq   a => Eq   (f a), Monad f) => Eq   (Semi f)
deriving instance ( forall a . Eq   a => Eq   (f a)
                  , forall a . Ord  a => Ord  (f a), Monad f) => Ord  (Semi f)
deriving instance ( forall a . Show a => Show (f a))          => Show (Semi f)


importGraph
  :: ( Monad term
     , forall a . Eq  a => Eq  (term a)
     , forall a . Ord a => Ord (term a)
     )
  => (forall sig m
     .  (Has (A.Domain term Addr (Value (Semi term)) :+: Env Addr :+: A.Heap Addr (Value (Semi term)) :+: Reader Path.AbsRelFile :+: Reader Span) sig m, MonadFail m)
     => (term Addr -> m (Value (Semi term)))
     -> (term Addr -> m (Value (Semi term)))
     )
  -> [File (term Addr)]
  -> ( Heap (Value (Semi term))
     , [File (Either (Path.AbsRelFile, Span, String) (Value (Semi term)))]
     )
importGraph eval
  = run
  . evalFresh 0
  . runHeap
  . traverse (runFile eval)

runFile
  :: forall term m sig
  .  ( Has Fresh sig m
     , Has (State (Heap (Value (Semi term)))) sig m
     , Monad term
     , forall a . Eq  a => Eq  (term a)
     , forall a . Ord a => Ord (term a)
     )
  => (forall sig m
     .  (Has (A.Domain term Addr (Value (Semi term)) :+: Env Addr :+: A.Heap Addr (Value (Semi term)) :+: Reader Path.AbsRelFile :+: Reader Span) sig m, MonadFail m)
     => (term Addr -> m (Value (Semi term)))
     -> (term Addr -> m (Value (Semi term)))
     )
  -> File (term Addr)
  -> m (File (Either (Path.AbsRelFile, Span, String) (Value (Semi term))))
runFile eval file = traverse run file
  where run = runReader (filePath file)
            . runReader (fileSpan file)
            . runEnv
            . runFail
            . fmap fold
            . convergeTerm 0 (A.runHeap @Addr @(Value (Semi term)) . fix (\ eval' -> runDomain eval' . fix (cacheTerm . eval)))


runDomain :: (term Addr -> m (Value (Semi term))) -> DomainC term m a -> m a
runDomain eval = runReader eval . runDomainC

newtype DomainC term m a = DomainC { runDomainC :: ReaderC (term Addr -> m (Value (Semi term))) m a }
  deriving (Alternative, Applicative, Functor, Monad, MonadFail)

instance MonadTrans (DomainC term) where
  lift = DomainC . lift

-- FIXME: decompose into a product domain and two atomic domains
instance (Alternative m, Has (Env Addr :+: A.Heap Addr (Value (Semi term)) :+: Reader Path.AbsRelFile :+: Reader Span) sig m, MonadFail m) => Algebra (A.Domain term Addr (Value (Semi term)) :+: sig) (DomainC term m) where
  alg hdl sig ctx = case sig of
    L (L A.Unit) -> pure (mempty <$ ctx)
    L (R (L (A.Bool _  ))) -> pure (mempty <$ ctx)
    L (R (L (A.AsBool   _))) -> pure (True <$ ctx) <|> pure (False <$ ctx)
    L (R (R (L (A.String s)))) -> pure (Value (String s) mempty <$ ctx)
    L (R (R (L (A.AsString _)))) -> pure (mempty <$ ctx)
    L (R (R (R (L (A.Lam b   ))))) -> do
      path <- ask
      span <- ask
      pure (Value (Closure path span b) mempty <$ ctx)
    L (R (R (R (L (A.AsLam (Value v _)))))) -> case v of
      Closure _ _ b -> pure (b <$ ctx)
      String _      -> fail "expected closure, got String"
      Abstract      -> fail "expected closure, got Abstract"
    L (R (R (R (R (A.Record f))))) -> do
      eval <- DomainC ask
      fields <- for f $ \ (k, t) -> do
        addr <- alloc @Addr k
        v <- lift (eval t)
        v <$ A.assign @Addr @(Value (Semi term)) addr v
      pure (fold fields <$ ctx)
    L (R (R (R (R (A.AsRecord _))))) -> pure ([] <$ ctx)
    R other -> DomainC (alg (runDomainC . hdl) (R other) ctx)
