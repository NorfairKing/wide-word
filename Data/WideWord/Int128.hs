{-# LANGUAGE CPP #-}
{-# LANGUAGE MagicHash #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE StrictData #-}
{-# LANGUAGE UnboxedTuples #-}
{-# OPTIONS_GHC -funbox-strict-fields #-}

-----------------------------------------------------------------------------
---- |
---- Module      :  Data.WideWord.Int128
----
---- Maintainer  :  erikd@mega-nerd.com
---- Stability   :  experimental
---- Portability :  non-portable (GHC extensions and primops)
----
---- This module provides an opaque signed 128 bit value with the usual set
---- of typeclass instances one would expect for a fixed width unsigned integer
---- type.
---- Operations like addition, subtraction and multiplication etc provide a
---- "modulo 2^128" result as one would expect from a fixed width unsigned word.
-------------------------------------------------------------------------------

#include <MachDeps.h>

module Data.WideWord.Int128
  ( Int128 (..)
  , byteSwapInt128
  , showHexInt128
  , zeroInt128
  ) where

import Data.Bits (Bits (..), FiniteBits (..), shiftL)

import Data.WideWord.Word128

import Numeric

import Foreign.Ptr (Ptr, castPtr)
import Foreign.Storable (Storable (..))

import GHC.Enum (predError, succError)
import GHC.Int
import GHC.Prim
import GHC.Real ((%))
import GHC.Word


data Int128 = Int128
  { int128Hi64 :: {-# UNPACK #-} !Word64
  , int128Lo64 :: {-# UNPACK #-} !Word64
  }
  deriving Eq


byteSwapInt128 :: Int128 -> Int128
byteSwapInt128 (Int128 a1 a0) = Int128 (byteSwap64 a1) (byteSwap64 a0)


showHexInt128 :: Int128 -> String
showHexInt128 (Int128 a1 a0)
  | a1 == 0 = showHex a0 ""
  | otherwise = showHex a1 zeros ++ showHex a0 ""
  where
    h0 = showHex a0 ""
    zeros = replicate (16 - length h0) '0'

instance Show Int128 where
  show = show . toInteger

instance Read Int128 where
  readsPrec p s = [(fromInteger128 (x :: Integer), r) | (x, r) <- readsPrec p s]

instance Ord Int128 where
  compare = compare128

instance Bounded Int128 where
  minBound = Int128 0x8000000000000000 0
  maxBound = Int128 0x7fffffffffffffff maxBound

instance Enum Int128 where
  succ = succ128
  pred = pred128
  toEnum = toEnum128
  fromEnum = fromEnum128

instance Num Int128 where
  (+) = plus128
  (-) = minus128
  (*) = times128
  negate = negate128
  abs = abs128
  signum = signum128
  fromInteger = fromInteger128

instance Bits Int128 where
  (.&.) = and128
  (.|.) = or128
  xor = xor128
  complement = complement128
  shiftL = shiftL128
  unsafeShiftL = shiftL128
  shiftR = shiftR128
  unsafeShiftR = shiftR128
  rotateL = rotateL128
  rotateR = rotateR128

  bitSize _ = 128
  bitSizeMaybe _ = Just 128
  isSigned _ = False

  testBit = testBit128
  bit = bit128

  popCount = popCount128

instance FiniteBits Int128 where
  finiteBitSize _ = 128
  countLeadingZeros = countLeadingZeros128
  countTrailingZeros = countTrailingZeros128

instance Real Int128 where
  toRational x = toInteger128 x % 1

instance Integral Int128 where
  quot n d = fst (quotRem128 n d)
  rem n d = snd (quotRem128 n d)
  div n d = fst (divMod128 n d)
  mod n d = snd (divMod128 n d)
  quotRem = quotRem128
  divMod = divMod128
  toInteger = toInteger128

instance Storable Int128 where
  sizeOf _ = 2 * sizeOf (0 :: Word64)
  alignment _ = 2 * alignment (0 :: Word64)
  peek = peek128
  peekElemOff = peekElemOff128
  poke = poke128
  pokeElemOff = pokeElemOff128

-- -----------------------------------------------------------------------------
-- Functions for `Ord` instance.

compare128 :: Int128 -> Int128 -> Ordering
compare128 (Int128 a1 a0) (Int128 b1 b0) =
  case compare (int64OfWord64 a1) (int64OfWord64 b1) of
    EQ -> compare a0 b0
    LT -> LT
    GT -> GT
  where
    int64OfWord64 (W64# w) = I64# (word2Int# w)

-- -----------------------------------------------------------------------------
-- Functions for `Enum` instance.


succ128 :: Int128 -> Int128
succ128 (Int128 a1 a0)
  | a1 == 0x7fffffffffffffff && a0 == maxBound = succError "Int128"
  | otherwise =
      case a0 + 1 of
        0 -> Int128 (a1 + 1) 0
        s -> Int128 a1 s

pred128 :: Int128 -> Int128
pred128 (Int128 a1 a0)
  | a1 == 0x8000000000000000 && a0 == 0 = predError "Int128"
  | otherwise =
      case a0 of
        0 -> Int128 (a1 - 1) maxBound
        _ -> Int128 a1 (a0 - 1)

{-# INLINABLE toEnum128 #-}
toEnum128 :: Int -> Int128
toEnum128 i = Int128 0 (toEnum i)

{-# INLINABLE fromEnum128 #-}
fromEnum128 :: Int128 -> Int
fromEnum128 (Int128 _ a0) = fromEnum a0

-- -----------------------------------------------------------------------------
-- Functions for `Num` instance.

{-# INLINABLE plus128 #-}
plus128 :: Int128 -> Int128 -> Int128
plus128 (Int128 (W64# a1) (W64# a0)) (Int128 (W64# b1) (W64# b0)) =
  Int128 (W64# s1) (W64# s0)
  where
    (# c1, s0 #) = plusWord2# a0 b0
    s1a = plusWord# a1 b1
    s1 = plusWord# c1 s1a

{-# INLINABLE minus128 #-}
minus128 :: Int128 -> Int128 -> Int128
minus128 (Int128 (W64# a1) (W64# a0)) (Int128 (W64# b1) (W64# b0)) =
  Int128 (W64# d1) (W64# d0)
  where
    (# d0, c1 #) = subWordC# a0 b0
    a1c = minusWord# a1 (int2Word# c1)
    d1 = minusWord# a1c b1

times128 :: Int128 -> Int128 -> Int128
times128 (Int128 (W64# a1) (W64# a0)) (Int128 (W64# b1) (W64# b0)) =
  Int128 (W64# p1) (W64# p0)
  where
    (# c1, p0 #) = timesWord2# a0 b0
    p1a = timesWord# a1 b0
    p1b = timesWord# a0 b1
    p1c = plusWord# p1a p1b
    p1 = plusWord# p1c c1

{-# INLINABLE negate128 #-}
negate128 :: Int128 -> Int128
negate128 (Int128 (W64# a1) (W64# a0)) =
  case plusWord2# (not# a0) 1## of
    (# c, s #) -> Int128 (W64# (plusWord# (not# a1) c)) (W64# s)

{-# INLINABLE abs128 #-}
abs128 :: Int128 -> Int128
abs128 i@(Int128 a1 _)
  | testBit a1 63 = negate128 i
  | otherwise = i

{-# INLINABLE signum128 #-}
signum128 :: Int128 -> Int128
signum128 (Int128 a1 a0)
  | a1 == 0 && a0 == 0 = zeroInt128
  | testBit a1 63 = minusOneInt128
  | otherwise = oneInt128

{-# INLINABLE complement128 #-}
complement128 :: Int128 -> Int128
complement128 (Int128 a1 a0) = Int128 (complement a1) (complement a0)

fromInteger128 :: Integer -> Int128
fromInteger128 i =
  Int128 (fromIntegral $ i `shiftR` 64) (fromIntegral i)

-- -----------------------------------------------------------------------------
-- Functions for `Bits` instance.

{-# INLINABLE and128 #-}
and128 :: Int128 -> Int128 -> Int128
and128 (Int128 (W64# a1) (W64# a0)) (Int128 (W64# b1) (W64# b0)) =
  Int128 (W64# (and# a1 b1)) (W64# (and# a0 b0))

{-# INLINABLE or128 #-}
or128 :: Int128 -> Int128 -> Int128
or128 (Int128 (W64# a1) (W64# a0)) (Int128 (W64# b1) (W64# b0)) =
  Int128 (W64# (or# a1 b1)) (W64# (or# a0 b0))

{-# INLINABLE xor128 #-}
xor128 :: Int128 -> Int128 -> Int128
xor128 (Int128 (W64# a1) (W64# a0)) (Int128 (W64# b1) (W64# b0)) =
  Int128 (W64# (xor# a1 b1)) (W64# (xor# a0 b0))

-- Probably not worth inlining this.
shiftL128 :: Int128 -> Int -> Int128
shiftL128 w@(Int128 a1 a0) s
  | s == 0 = w
  | s < 0 = shiftL128 w (128 - (abs s `mod` 128))
  | s >= 128 = zeroInt128
  | s == 64 = Int128 a0 0
  | s > 64 = Int128 (a0 `shiftL` (s - 64)) 0
  | otherwise =
      Int128 s1 s0
      where
        s0 = a0 `shiftL` s
        s1 = a1 `shiftL` s + a0 `shiftR` (64 - s)

-- Probably not worth inlining this.
shiftR128 :: Int128 -> Int -> Int128
shiftR128 i@(Int128 a1 a0) s
  | s < 0 = zeroInt128
  | s == 0 = i
  | topBitSetWord64 a1 = complement128 (shiftR128 (complement128 i) s)
  | s >= 128 = zeroInt128
  | s == 64 = Int128 0 a1
  | s > 64 = Int128 0 (a1 `shiftR` (s - 64))
  | otherwise = Int128 s1 s0
      where
        s1 = a1 `shiftR` s
        s0 = a0 `shiftR` s + a1 `shiftL` (64 - s)

rotateL128 :: Int128 -> Int -> Int128
rotateL128 w@(Int128 a1 a0) r
  | r < 0 = zeroInt128
  | r == 0 = w
  | r >= 128 = rotateL128 w (r `mod` 128)
  | r == 64 = Int128 a0 a1
  | r > 64 = rotateL128 (Int128 a0 a1) (r `mod` 64)
  | otherwise =
      Int128 s1 s0
      where
        s0 = a0 `shiftL` r + a1 `shiftR` (64 - r)
        s1 = a1 `shiftL` r + a0 `shiftR` (64 - r)

rotateR128 :: Int128 -> Int -> Int128
rotateR128 w@(Int128 a1 a0) r
  | r < 0 = rotateR128 w (128 - (abs r `mod` 128))
  | r == 0 = w
  | r >= 128 = rotateR128 w (r `mod` 128)
  | r == 64 = Int128 a0 a1
  | r > 64 = rotateR128 (Int128 a0 a1) (r `mod` 64)
  | otherwise =
      Int128 s1 s0
      where
        s0 = a0 `shiftR` r + a1 `shiftL` (64 - r)
        s1 = a1 `shiftR` r + a0 `shiftL` (64 - r)

testBit128 :: Int128 -> Int -> Bool
testBit128 (Int128 a1 a0) i
  | i < 0 = False
  | i >= 128 = False
  | i >= 64 = testBit a1 (i - 64)
  | otherwise = testBit a0 i

bit128 :: Int -> Int128
bit128 indx
  | indx < 0 = zeroInt128
  | indx >= 128 = zeroInt128
  | otherwise = shiftL128 oneInt128 indx

popCount128 :: Int128 -> Int
popCount128 (Int128 a1 a0) = popCount a1 + popCount a0

-- -----------------------------------------------------------------------------
-- Functions for `FiniteBits` instance.

countLeadingZeros128 :: Int128 -> Int
countLeadingZeros128 (Int128 a1 a0) =
  case countLeadingZeros a1 of
    64 -> 64 +  countLeadingZeros a0
    res -> res

countTrailingZeros128 :: Int128 -> Int
countTrailingZeros128 (Int128 a1 a0) =
  case countTrailingZeros a0 of
    64 -> 64 + countTrailingZeros a1
    res -> res

-- -----------------------------------------------------------------------------
-- Functions for `Integral` instance.

quotRem128 :: Int128 -> Int128 -> (Int128, Int128)
quotRem128 numer denom
  | numerIsNegative && denomIsNegative = (word128ToInt128 wq, word128ToInt128 (negate wr))
  | numerIsNegative = (word128ToInt128 (negate wq), word128ToInt128 (negate wr))
  | denomIsNegative = (word128ToInt128 (negate wq), word128ToInt128 wr)
  | otherwise = (word128ToInt128 wq, word128ToInt128 wr)
  where
    (wq, wr) = quotRem absNumerW absDenomW
    absNumerW = int128ToWord128 $ abs128 numer
    absDenomW = int128ToWord128 $ abs128 denom
    numerIsNegative = topBitSetWord64 $ int128Hi64 numer
    denomIsNegative = topBitSetWord64 $ int128Hi64 denom


divMod128 :: Int128 -> Int128 -> (Int128, Int128)
divMod128 numer denom
  | numerIsNegative && denomIsNegative = (word128ToInt128 wq, word128ToInt128 (negate wr))
  | numerIsNegative = (word128ToInt128 (negate $ wq + 1), word128ToInt128 (absDenomW - wr))
  | denomIsNegative = (word128ToInt128 (negate $ wq + 1), word128ToInt128 (negate $ absDenomW - wr))
  | otherwise = (word128ToInt128 wq, word128ToInt128 wr)
  where
    (wq, wr) = quotRem absNumerW absDenomW
    numerIsNegative = topBitSetWord64 $ int128Hi64 numer
    denomIsNegative = topBitSetWord64 $ int128Hi64 denom
    absNumerW = int128ToWord128 $ abs128 numer
    absDenomW = int128ToWord128 $ abs128 denom


toInteger128 :: Int128 -> Integer
toInteger128 i@(Int128 a1 a0)
  | popCount a1 == 64 && popCount a0 == 64 = -1
  | not (testBit a1 63) = fromIntegral a1 `shiftL` 64 + fromIntegral a0
  | otherwise =
      case negate128 i of
        Int128 n1 n0 -> negate (fromIntegral n1 `shiftL` 64 + fromIntegral n0)

-- -----------------------------------------------------------------------------
-- Functions for `Integral` instance.

peek128 :: Ptr Int128 -> IO Int128
peek128 ptr =
  Int128 <$> peekElemOff (castPtr ptr) index1 <*> peekElemOff (castPtr ptr) index0

peekElemOff128 :: Ptr Int128 -> Int -> IO Int128
peekElemOff128 ptr idx =
  Int128 <$> peekElemOff (castPtr ptr) (2 * idx + index1)
            <*> peekElemOff (castPtr ptr) (2 * idx + index0)

poke128 :: Ptr Int128 -> Int128 -> IO ()
poke128 ptr (Int128 a1 a0) =
  pokeElemOff (castPtr ptr) index1 a1 >> pokeElemOff (castPtr ptr) index0 a0

pokeElemOff128 :: Ptr Int128 -> Int -> Int128 -> IO ()
pokeElemOff128 ptr idx (Int128 a1 a0) = do
  pokeElemOff (castPtr ptr) (2 * idx + index0) a0
  pokeElemOff (castPtr ptr) (2 * idx + index1) a1

-- -----------------------------------------------------------------------------
-- Helpers.

{-# INLINE int128ToWord128 #-}
int128ToWord128 :: Int128 -> Word128
int128ToWord128 (Int128 a1 a0) = Word128 a1 a0

{-# INLINE topBitSetWord64 #-}
topBitSetWord64 :: Word64 -> Bool
topBitSetWord64 w = testBit w 63

{-# INLINE word128ToInt128 #-}
word128ToInt128 :: Word128 -> Int128
word128ToInt128 (Word128 a1 a0) = Int128 a1 a0

-- -----------------------------------------------------------------------------
-- Constants.

zeroInt128 :: Int128
zeroInt128 = Int128 0 0

oneInt128 :: Int128
oneInt128 = Int128 0 1

minusOneInt128 :: Int128
minusOneInt128 = Int128 maxBound maxBound

index0, index1 :: Int
#if WORDS_BIGENDIAN
index0 = 1
index1 = 0
#else
index0 = 0
index1 = 1
#endif
