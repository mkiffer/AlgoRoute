-- hspec-discover auto-collects every module named *Spec under test/ that
-- exports `spec :: Spec`. Adding a new test file needs no wiring here — just
-- name it <Thing>Spec.hs and export `spec`. `cabal test` runs them all.
{-# OPTIONS_GHC -F -pgmF hspec-discover #-}
