{-# LANGUAGE CPP #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveAnyClass #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE QuantifiedConstraints #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# OPTIONS_GHC -fno-warn-unused-imports #-}

module Language.PHP.AST
( module Language.PHP.AST
) where

import           AST.GenerateSyntax
import           AST.Token()
import           Language.Haskell.TH.Syntax (runIO)
import           Prelude hiding (String, Integer, Float)
import qualified TreeSitter.PHP as PHP (getNodeTypesPath, tree_sitter_php)

#ifdef NODE_TYPES_PATH
astDeclarationsForLanguage PHP.tree_sitter_php NODE_TYPES_PATH
#else
runIO PHP.getNodeTypesPath >>= astDeclarationsForLanguage PHP.tree_sitter_php
#endif
