-- |
-- Test suite entry point.
--
-- The spec tree itself is assembled by @hspec-discover@ in "SpecTree": it scans
-- @test\/@ for files ending in @Spec.hs@ and stitches their @spec@ values
-- together, so adding a new @*Spec.hs@ file is all that is needed to have it
-- run — no registration list to keep in sync.
--
-- The only reason this file is hand-written rather than a one-line
-- @hspec-discover@ shim is the two 'hSetEncoding' calls. Test descriptions in
-- this suite contain @km²@, @→@ and other non-ASCII characters, and a Haskell
-- 'System.IO.Handle' takes its encoding from the process locale. Under
-- @LANG=C@ — the default in many containers and CI images — printing one of
-- those throws @commitBuffer: invalid argument@ and the whole suite dies
-- mid-run. Two lines make the output encoding explicit instead of ambient.
module Main (main) where

import SpecTree (spec)
import System.IO (hSetEncoding, stderr, stdout, utf8)
import Test.Hspec (hspec)

main :: IO ()
main = do
  hSetEncoding stdout utf8
  hSetEncoding stderr utf8
  hspec spec
