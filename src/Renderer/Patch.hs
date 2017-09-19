import Data.ByteString.Char8 (ByteString, pack)
import Data.Maybe (fromMaybe)
import Data.Monoid (Sum(..))
import Data.Output
import Data.Semigroup ((<>))
import Prelude hiding (fst, snd)
renderPatch :: (HasField fields Range, Traversable f) => Both Blob -> Diff f (Record fields) (Record fields) -> File
instance Output File where
  toOutput = unFile
        offsetHeader = "@@ -" <> offsetA <> "," <> pack (show lengthA) <> " +" <> offsetB <> "," <> pack (show lengthB) <> " @@" <> "\n"
        (offsetA, offsetB) = runJoin . fmap (pack . show . getSum) $ offset hunk
        (pathA, pathB) = case runJoin $ pack . blobPath <$> blobs of
hunks :: (Traversable f, HasField fields Range) => Diff f (Record fields) (Record fields) -> Both Blob -> [Hunk (SplitDiff [] (Record fields))]

maybeSnd :: These a b -> Maybe b
maybeSnd = these (const Nothing) Just (\ _ a -> Just a)