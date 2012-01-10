Filters = require 'BloomFilter'

describe 'BloomFilter', ->
  bf = new Filters.BloomFilter(10)

  it 'would have no elements in it with no data', ->
    expect(bf.count).toEqual(0)

  it 'could add one and would be good', ->
    expect(bf.has("one")).toBeFalsy()
    expect(bf.has("two")).toBeFalsy()
    bf.add("one")
    expect(bf.count).toEqual(1)
    expect(bf.has("one")).toBeTruthy() # <!-- trouble
    expect(bf.has("two")).toBeFalsy()

  it 'test capacity of 10 - add 10 things', ->
    cnt=0
    bf.add("k#{cnt++}") while cnt < 10
    cnt=0
    expect(bf.has("k#{cnt++}")).toBeTruthy() while cnt < 10
    cnt=0
    bf.add("k-#{cnt++}") while cnt < 10
    cnt=0
    expect(bf.has("k-#{cnt++}")).toBeTruthy() while cnt < 10
    cnt=0
    expect(bf.has("k#{cnt++}")).toBeTruthy() while cnt < 10
    # TODO test a false positive...

  it 'has a copy constructor', ->
    bf2 = new Filters.BloomFilter(bf.capacity,bf.errorRate,bf.filter,bf.count)
    cnt=0
    expect(bf.has("k#{cnt++}")).toBeTruthy() while cnt < 10
    bf3 = Filters.BloomFilter.fromJSON(JSON.parse(JSON.stringify(bf2)))
    expect(bf3.slices[0] instanceof Filters.ArrayBitSet).toBeTruthy()
    expect(bf3.has("k#{cnt++}")).toBeTruthy() while cnt < 10
    robf = bf.readOnlyInstance()
    expect(robf.has("k#{cnt++}")).toBeTruthy() while cnt < 10
    expect(robf.slices[0] instanceof Filters.ConciseBitSet).toBeTruthy()
    robf2 = Filters.BloomFilter.fromJSON(JSON.parse(JSON.stringify(robf)))
    expect(robf2.has("k#{cnt++}")).toBeTruthy() while cnt < 10
    expect(robf2.slices[0] instanceof Filters.ConciseBitSet).toBeTruthy()

  it 'can be made read only', ->
    sz = 100
    bf = new Filters.BloomFilter(sz)
    bf.add("k#{cnt}") for cnt in [0..sz]
    robf = bf.readOnlyInstance()
    expect(bf.has("k#{cnt}")).toBeTruthy() for cnt in [0..sz]
    expect(robf.has("k#{cnt}")).toBeTruthy() for cnt in [0..sz]

    ###
    console.log "BF:"
    s.printObject() for s in bf.slices
    console.log "ROBF:"
    s.printObject() for s in robf.slices
    ###

    ###
    numbers = 0
    numbers += s.data.length for s in bf.slices
    console.log "BF: #{numbers}"
    numbers = 0
    numbers += s.words.length for s in robf.slices
    console.log "ROBF: #{numbers} "
    ###

    #console.log "len = #{bf.sliceLen}"
    ###
    for i in [0..bf.sliceLen-1]
      for s,si in bf.slices
        console.log "comparing sb to robf #{i} of #{si}: #{s.has(i)} =? #{robf.slices[si].has(i)}"
        expect(s.has(i)).toEqual(robf.slices[si].has(i))
    ###

describe 'ArrayBitSet', ->
  abs = new Filters.ArrayBitSet(100)
  it 'can convert a bit offset to the number and bit of the number', ->
    expect(abs.computeIndexes(0)).toEqual([0,0])
    expect(abs.computeIndexes(1)).toEqual([0,1])
    expect(abs.computeIndexes(32)).toEqual([1,0])
    expect(abs.computeIndexes(35)).toEqual([1,3])

  it 'can convert to a CONCISE bitset', ->
    abs = new Filters.ArrayBitSet(100)
    cbs = abs.toConciseBitSet()
    expect(cbs.has(i)).toBeFalsy() for i in [0..110]
    abs.add(5)
    cbs = abs.toConciseBitSet()
    expect(abs.has(5)).toBeTruthy()
    expect(cbs.has(5)).toBeTruthy()
    expect(cbs.has(i)).toBeFalsy() for i in [0..4]
    expect(cbs.has(i)).toBeFalsy() for i in [6..110]
    abs = new Filters.ArrayBitSet(200)
    abs.add(42)
    abs.add(99)
    abs.add(110)
    cbs = abs.toConciseBitSet()
    #cbs.printObject()
    expect(abs.has(i)).toBeTruthy() for i in [42,99,110]
    expect(cbs.has(i)).toBeTruthy() for i in [42,99,110]
    expect(cbs.has(i)).toBeFalsy() for i in [0..41]
    expect(cbs.has(i)).toBeFalsy() for i in [43..98]
    expect(cbs.has(i)).toBeFalsy() for i in [100..109]

describe 'ScalableBloomFilter', ->
  bf = new Filters.ScalableBloomFilter(10,0.00001)

  it 'would start with one filter', -> expect(bf.filters.length).toEqual(1)

  it 'would make a new filter after 10 inserts', ->
    expect(bf.count).toEqual(0)
    for i in [1..11]
      bf.add("key #{i}")
      expect(bf.count).toEqual(i)
    expect(bf.has("key #{i}")).toBeTruthy() for i in [1..11] # <--- failure
    expect(bf.filters.length).toEqual(2)
    expect(bf.filters[0].sliceLen < bf.filters[1].sliceLen).toBeTruthy()
    # the error rate of subsequent blooms should be tighter
    expect(bf.filters[0].errorRate > bf.filters[1].errorRate).toBeTruthy()
    expect(bf.filters[0].capacity < bf.filters[1].capacity).toBeTruthy()

  it 'has a copy constructor', ->
    bf2 = new Filters.ScalableBloomFilter(bf.startcapacity,bf.targetErrorRate,bf.filters,bf.stages,bf.r,bf.count)
    expect(bf.count).toEqual(11)
    expect(bf2.count).toEqual(11)
    expect(bf2.has("key #{i}")).toBeTruthy() for i in [1..11]
    robf = bf2.readOnlyInstance()
    expect(robf.has("key #{i}")).toBeTruthy() for i in [1..11]
    bf2 = Filters.ScalableBloomFilter.fromJSON(JSON.parse(JSON.stringify(bf)))
    expect(bf2.filters[0] instanceof Filters.StrictBloomFilter).toBeTruthy()
    expect(bf2.filters[0].slices[0] instanceof Filters.ArrayBitSet).toBeTruthy()
    expect(bf2.has("key #{i}")).toBeTruthy() for i in [1..11]
    robf2 = Filters.ScalableBloomFilter.fromJSON(JSON.parse(JSON.stringify(robf)))
    expect(robf2.filters[0] instanceof Filters.StrictBloomFilter).toBeTruthy()
    expect(robf2.filters[0].slices[0] instanceof Filters.ConciseBitSet).toBeTruthy()
    expect(robf2.has("key #{i}")).toBeTruthy() for i in [1..11]
 
 describe 'ConciseBitSet', ->
  cbs = new Filters.ConciseBitSet()

  it 'would start out empty', -> expect(cbs.top).toEqual(0)

  it 'would contain a number if you added it - one word', ->
    cbs = new Filters.ConciseBitSet()
    cbs.add(1)
    expect(cbs.max).toEqual(1)
    expect(cbs.bitCount()).toEqual(1)
    expect(cbs.has(1)).toBeTruthy()
    cbs.add(10)
    expect(cbs.max).toEqual(10)
    expect(cbs.bitCount()).toEqual(2)
    expect(cbs.has(i)).toBeFalsy() for i in [2..9]
    expect(cbs.has(10)).toBeTruthy()

  it 'would work for each type', ->
    cbs = new Filters.ConciseBitSet()
    cbs.add(i) for i in [0..30]
    expect(cbs.max).toEqual(30)
    expect(cbs.bitCount()).toEqual(31)
    expect(cbs.has(i)).toBeTruthy() for i in [0..30]
    expect(cbs.top).toEqual(0)
    expect(cbs.max).toEqual(30)

    cbs.add(31)
    expect(cbs.bitCount()).toEqual(32)
    expect(cbs.top).toEqual(1)
    expect(cbs.max).toEqual(31)

    cbs.add(32)
    expect(cbs.bitCount()).toEqual(33)
    expect(cbs.top).toEqual(1)
    ###
    cbs.printObject()
    ###

  it 'would work for the paper example.', ->
    cbs = new Filters.ConciseBitSet()
    cbs.add(3)
    cbs.add(5)
    expect(cbs.bitStringAsWord('1000 0000 0000 0000 0000 0000 0010 1000')).toEqual(cbs.words[0])
    cbs.add(i) for i in [31..93]
    expect(cbs.bitStringAsWord('1000 0000 0000 0000 0000 0000 0010 1000')).toEqual(cbs.words[0])
    expect(cbs.bitStringAsWord('0100 0000 0000 0000 0000 0000 0000 0001')).toEqual(cbs.words[1])
    expect(cbs.bitStringAsWord('1000 0000 0000 0000 0000 0000 0000 0001')).toEqual(cbs.words[2])
    cbs.add(1024)
    cbs.add(1028)
    #cbs.printObject()
    cbs.add(1040187422)
    expect(cbs.max).toEqual(1040187422)
    expect(cbs.top).toEqual(5)
    expect(cbs.bitStringAsWord('1000 0000 0000 0000 0000 0000 0010 0010')).toEqual(cbs.words[3])
    expect(cbs.bitStringAsWord('0000 0001 1111 1111 1111 1111 1101 1101')).toEqual(cbs.words[4])
    expect(cbs.bitStringAsWord('1100 0000 0000 0000 0000 0000 0000 0000')).toEqual(cbs.words[5])
    #cbs.printObject()

  it 'has support functions that show the bits correctly', ->
    cbs = new Filters.ConciseBitSet()
    expect(cbs.bitOfWordSet(0,0)).toBeFalsy()
    expect(cbs.bitsOfWordSet(0)).toEqual(0)
    expect(cbs.bitOfWordSet(1,0)).toBeTruthy()
    expect(cbs.bitsOfWordSet(1)).toEqual(1)
    expect(cbs.wordAsBitString(1)).toEqual('0000 0000 0000 0000 0000 0000 0000 0001')
    expect(cbs.bitStringAsWord('0000 0000 0000 0000 0000 0000 0000 0001')).toEqual(1)
    expect(cbs.bitStringAsWord('0000 0000 0000 0000 0000 0000 0001 0001')).toEqual(17)
    expect(cbs.bitStringAsWord('1000 0000 0000 0000 0000 0000 0000 0001')).toEqual(-2147483647)
    expect(cbs.bitStringAsWord('0100 0000 0000 0000 0000 0000 0000 0001')).toEqual(1073741825)
    expect(cbs.wordAsBitString(-2147483647)).toEqual('1000 0000 0000 0000 0000 0000 0000 0001')
    expect(cbs.bitOfWordSet(-2147483647,31)).toBeTruthy()
    expect(cbs.bitsOfWordSet(-2147483647)).toEqual(2)
    expect(cbs.wordMatches(0,0x00000000)).toBeTruthy()
    expect(cbs.wordMatches(0,0x00000001)).toBeFalsy()
    expect(cbs.wordMatches(1,0x00000001)).toBeTruthy()
    expect(cbs.wordMatches(0xffffffff,0xffffffff)).toBeTruthy()

  it 'can do bitcount properly', ->
    cbs = new Filters.ConciseBitSet()
    expect(cbs.bitCount([])).toEqual(0)
    expect(cbs.bitCount([1])).toEqual(0)
    expect(cbs.bitCount([-2147483647])).toEqual(1)
    expect(cbs.bitCount([1073741824])).toEqual(31)
    expect(cbs.bitCount([1073741825])).toEqual(62)

  it 'can do a propery trailing zeros', ->
    cbs = new Filters.ConciseBitSet()
    expect(cbs.trailingZeros(0)).toEqual(32)
    expect(cbs.trailingZeros(1)).toEqual(0)
    expect(cbs.trailingZeros(2)).toEqual(1)

  it '42 and 110?', ->
    cbs = new Filters.ConciseBitSet()
    cbs.add(42)
    expect(cbs.has(42)).toBeTruthy()
    #cbs.printObject()
    cbs.add(99)
    expect(cbs.has(42)).toBeTruthy()
    expect(cbs.has(99)).toBeTruthy()
    cbs.add(110)
    expect(cbs.has(42)).toBeTruthy()
    expect(cbs.has(99)).toBeTruthy()
    expect(cbs.has(110)).toBeTruthy()
    #cbs.printObject()
