import math, complex, strutils, collections, sequtils

when not compiles(Complex64):
  type Complex64 = Complex

proc toComplex(x: float): Complex64 =
  result.re = x

proc toComplex(re: float, im: float): Complex64 =
  result.re = re
  result.im = im

# Works with floats and complex numbers as input
proc fft(x: openarray[float]): seq[Complex64] =
  let n = x.len
  result = newSeq[Complex64]()
  if n <= 1:
    for v in x: result.add toComplex(v)
    return
  var evens, odds = newSeq[float]()
  for i, v in x:
    if i mod 2 == 0: evens.add v
    else: odds.add v
  var (even, odd) = (fft(evens), fft(odds))

  for k in 0 ..< (n div 2):
    result.add(even[k] + exp(toComplex(0.0, -2*PI*float(k)/float(n))) * odd[k])

  for k in 0 ..< (n div 2):
    result.add(even[k] - exp(toComplex(0.0, -2*PI*float(k)/float(n))) * odd[k])

proc getFreq*(data: Buffer): int =
  var samples: seq[float]
  for i in 0..<(data.len div 4):
    let ch1 = unpack(data[i*4..i*4 + 1], int16).float
    let ch2 = unpack(data[i*4 + 2..i*4 + 3], int16).float
    let val16 = (ch1 + ch2) / 2 # average the two channels
    samples.add(val16 / float(int16.high))

  var power = fft(samples).mapIt(abs(it))
  return argmax(power[0..<len(power) div 2])

proc makeSignal*(length: int, freq: int): Buffer =
  var data = ""
  for i in 0..<length:
    let p = sin(2 * PI * float(freq) * float(i)/float(length))
    let p16 = int16(float(int16.high) * p)
    data &= pack(p16)
    data &= pack(p16)

  return data

when isMainModule:
  for i in 2..10:
    let sig = makeSignal(64, i)
    assert getFreq(sig) == i
