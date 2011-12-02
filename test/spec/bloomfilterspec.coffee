Filters = require 'lib/BloomFilter'

describe 'BloomFilter', ->
  bf = new Filters.BloomFilter(10)

  it 'would have no elements in it with no data', ->
    expect(bf.count).toEqual(0)

  it 'could add one and would be good', ->
    expect(bf.has("one")).toBeFalsy()
    expect(bf.has("two")).toBeFalsy()
    bf.add("one")
    expect(bf.count).toEqual(1)
    expect(bf.has("one")).toBeTruthy()
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

  it 'can convert a bit offset to the number and bit of the number', ->
    expect(bf.computeIndexes(0)).toEqual([0,0])
    expect(bf.computeIndexes(1)).toEqual([0,1])
    expect(bf.computeIndexes(32)).toEqual([1,0])
    expect(bf.computeIndexes(35)).toEqual([1,3])

describe 'ScalableBloomFilter', ->
  bf = new Filters.ScalableBloomFilter(10)

  it 'would start with one filter', -> expect(bf.filters.length).toEqual(1)

  it 'would make a new filter after 10 inserts', ->
    bf.add("key #{i}") for i in [1..11]
    expect(bf.has("key #{i}")).toBeTruthy() for i in [1..11]
    expect(bf.filters.length).toEqual(2)
    expect(bf.filters[0].sliceLen < bf.filters[1].sliceLen).toBeTruthy()
    # the error rate of subsequent blooms should be tighter
    expect(bf.filters[0].errorRate > bf.filters[1].errorRate).toBeTruthy()

  it 'has a copy constructor', ->
    bf2 = new Filters.ScalableBloomFilter(bf.startcapacity,bf.errorRate,bf.filters,bf.stages,bf.r,bf.count)
    expect(bf2.has("key #{i}")).toBeTruthy() for i in [1..11]
