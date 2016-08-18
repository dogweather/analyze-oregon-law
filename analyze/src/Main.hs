{-# LANGUAGE UnicodeSyntax #-}

module Main where

import           Amendment
import           Control.Arrow.Unicode
import           Control.Monad
import           Data.Aeson.Encode.Pretty (encodePretty)
import qualified Data.ByteString.Lazy     as B
import           Data.List                (isPrefixOf, nub, sort)
import           Data.Time                (fromGregorian)
import           GHC.IO.Exception
import           Prelude.Unicode
import           StringOps
import           System.Environment       (getArgs)
import           System.Process           (readProcessWithExitCode)
import           Text.HandsomeSoup
import           Text.Regex.TDFA
import           Text.XML.HXT.Core        (getText, hread, runLA, (//>), (>>>))



main ∷ IO ()
main = do
  args ← getArgs
  when (length args /= 1) $
    fail "Usage: analyze [filename]"

  let pdfFilename = head args
  (errCode, rawHTML, stderr') ← runTika pdfFilename
  when (errCode /= ExitSuccess) $
    fail stderr'

  rawHTML
    |> tikaOutputToJson
    |> B.putStr


runTika ∷ String → IO (ExitCode, String, String)
runTika pdfFilename =
  readProcessWithExitCode "java" ["-jar", "/Users/robb/lib/tika-app.jar", "--html", pdfFilename] ""


tikaOutputToJson ∷ String → B.ByteString
tikaOutputToJson = makeAmendment ⋙ encodePretty


makeAmendment ∷ String → Amendment
makeAmendment html =
  let phrases = html |> paragraphs
  in Amendment {
    summary    = phrases |> findSummary,
    citations  = phrases |> findSectionNumbers,
    bill       = html |> findCitation |> makeBill,
    year       = html |> findYear,
    effectiveDate = phrases |> findEffectiveDate
  }


paragraphs ∷ String → [String]
paragraphs html =
  -- TODO: Switch to TagSoup for the HTML parsing
  let allParagraphs = runLA (hread >>> css "p" //> getText) html
  in filter (not ∘ isPdfMetadata) allParagraphs


findSummary ∷ [String] → String
findSummary phrases =
  case filter isSummary phrases of
    [aSummary] → cleanUp aSummary
    _          → "(Summary is not available)"


findSectionNumbers ∷ [String] → [SectionNumber]
findSectionNumbers phrases =
  phrases
    |> map sectionNumbers
    |> flatten
    |> unique
    |> sort


sectionNumbers ∷ String → [String]
sectionNumbers phrase =
  -- Match ORS section numbers like 40.230 and 743A.144.
  getAllTextMatches (phrase =~ "[0-9]{1,3}[A-C]?\\.[0-9]{3}")


isPdfMetadata ∷ String → Bool
isPdfMetadata text =
  "<<\n" `isPrefixOf` text


flatten = concat
unique = nub
