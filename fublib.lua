--------------------------------------------------------------------------------
-- Helper functions for wrapping and unwrapping the context (state) object.
--------------------------------------------------------------------------------
-- We define the most common wrapContext functions, since at lower parameter count
-- manual passing of the additional parameters is faster than using table.unpack

-- Wraps a context object in a factory function with one additional parameter.
---@param enumerator Enumerator3
---@return fun():table
local wrapContext0 = function(enumerator)
    local nextFunc, context = enumerator.nextFunc, enumerator.contextFactory
    return function() return { 0, nextFunc, context } end
end

-- Wraps a context object in a factory function with one additional parameter.
---@param enumerator Enumerator3
---@param param1 any
---@return fun():table
local wrapContext1 = function(enumerator, param1)
    local nextFunc, context = enumerator.nextFunc, enumerator.contextFactory
    return function() return { 0, nextFunc, context, param1 } end
end

-- Wraps a context object in a factory function with two additional parameters.
---@param enumerator Enumerator3
---@param param1 any
---@param param2 any
---@return fun():table
local wrapContext2 = function(enumerator, param1, param2)
    local nextFunc, context = enumerator.nextFunc, enumerator.contextFactory
    return function() return { 0, nextFunc, context, param1, param2 } end
end

-- Wraps a context object in a factory function with N additional parameters.
---@param enumerator Enumerator3
---@param ... unknown
---@return fun():table
local wrapContextN = function(enumerator, ...)
    local nextFunc, context = enumerator.nextFunc, enumerator.contextFactory
    local varargs = {...}
    return function() return { 0, nextFunc, context, table.unpack(varargs) } end
end

local ipairsFunc = ipairs({0})
local pairsFunc = pairs({'a'})

local getIterator

-- Sets the state to the context, and returns the state
---@param context table
---@param state integer
---@return integer
local setState = function(context, state)
    context[1] = state
    return state
end

-- Replaces the context factory with the context returned from the factory.
---@param context table
---@return table?
local initialiseContext = function(context)
    local contextFactory = context[3]
    if contextFactory == nil then
        return nil
    else
        -- Call the factory method and replace the factory method with the
        -- unpacked context so its state is available for mutation.
        local newContext = contextFactory()
        context[3] = newContext
        return newContext
    end
end

-- Grabs the next item from a raw iterator and stores replaces the index with the next index.
-- This is used as a shortcut for advancing nested iterators / tables.
---@param iterator table
---@return any
---@return any
local moveIterator = function(iterator)
    local iteratorFunction, context, index = iterator[1], iterator[2], iterator[3]
    index, context = iteratorFunction(context, index)
    iterator[3] = index
    return index, context
end

--------------------------------------------------------------------------------
-- Helper functions for hashset behaviour
--------------------------------------------------------------------------------
---@param set table
---@param item any
---@return boolean
local addToSet = function(set, item)
    if set[item] == nil then
        set[item] = true
        return true
    end
    return false
end

---@param set table
---@param item any
---@return boolean
local removeFromSet = function(set, item)
    if set[item] == nil then
        return false
    end
    set[item] = nil
    return true
end

--------------------------------------------------------------------------------
-- Enumerator object definition.
--------------------------------------------------------------------------------
--- @class Enumerator3
--- @field nextFunc fun(context: any, index: any):any, any
--- @field index any
--- @field contextFactory fun(): table
local Enumerator3 = {
    __call = function(self, param, state)
        return self.nextFunc(self.contextFactory(), state)
    end;
    __pairs = function(self)
        return self.nextFunc, self.contextFactory(), self.index
    end;
    __ipairs = function(self)
        return self.nextFunc, self.contextFactory(), self.index
    end;
}
Enumerator3.__index = Enumerator3

---@param nextFunc fun(context: any, index: any):any, any
---@param index any
---@param contextFactory fun(): any
---@return Enumerator3
function Enumerator3.new(nextFunc, index, contextFactory)
    return setmetatable({
        nextFunc = nextFunc,
        index = index,
        contextFactory = contextFactory
    }, Enumerator3)
end

---@param obj any
---@return Enumerator3
function Enumerator3.create(obj)
    local func, current, index = getIterator(obj)
    return Enumerator3.new(func, index, function() return current end)
end

function Enumerator3.createWith(obj, iterator)
    local func, current, index = iterator(obj)
    return Enumerator3.new(func, index, function() return current end)
end

--------------------------------------------------------------------------------
-- Helper function for setting up iterator.
--------------------------------------------------------------------------------
getIterator = function(obj, context, index)
    assert(obj ~= nil, 'invalid iterator')
    if type(obj) == 'table' then
        local mt = getmetatable(obj);
        if mt ~= nil then
            if mt == Enumerator3 then
                return obj.nextFunc, obj.contextFactory(), obj.index
            elseif mt.__ipairs ~= nil then
                return mt.__ipairs(obj)
            elseif mt.__pairs ~= nil then
                return mt.__pairs(obj)
            end
        end
        if obj._isIterator == true then
            return obj[1], obj[2](), obj[3]
        end
        if #obj > 0 then
            return ipairs(obj)
        else
            return pairs(obj)
        end
    elseif (type(obj) == 'function') then
        -- This is likely a contextFactory. Unwrap it if it's the case.
        if type(context) == 'function' then context = context() end
        return obj, context, index
    end

    error(string.format('object %s of type "%s" is not iterable', obj, type(obj)))
end

--------------------------------------------------------------------------------
-- Chainable functions
--------------------------------------------------------------------------------

-- WHERE
local whereFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]

    if state ~= 0 then
        if state ~= 1 then
            return nil, nil
        end
    else
        -- Unpack context
        nextContext = initialiseContext(context)
        state = setState(context, 1)
    end

    local predicate = context[4]
    local current

    while true do
        index, current = nextFunc(nextContext, index)
        if index == nil then
            setState(context, -4)
            return nil, nil
        end
        if predicate(current, index) == true then
            return index, current
        end
    end
end

---Filters a sequence of values based on a predicate.
---@param predicate fun(item: any, index: any): boolean
---@return Enumerator3
function Enumerator3:where(predicate)
    assert(predicate, 'Predicate cannot be nil')
    return Enumerator3.new(whereFunc, self.index, wrapContext1(self, predicate))
end


-- MAP / SELECT
local mapFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]

    if state ~= 0 then
        if state ~= 1 then
            return nil, nil
        end
    else
        -- Initialise
        nextContext = initialiseContext(context)
        state = setState(context, 1)
    end

    local selector = context[4]
    local position = context[5] + 1
    local current

    index, current = nextFunc(nextContext, index)
    if index ~= nil then
        current = selector(current, position)
        assert(current, 'Selected value must be non-nil')
        context[5] = position
        return index, current
    end

    setState(context, -4)
end

---Projects each element of a sequence into a new form.
---@param selector fun(item: any, position: integer): any
---@return Enumerator3
function Enumerator3:map(selector)
    assert(selector, 'Selector cannot be nil')
    return Enumerator3.new(mapFunc, self.index, wrapContext2(self, selector, 0))
end


-- FLATMAP / SELECTMANY
local flatMapFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: Predicate
    -- 5: Position
    -- 6: Parent Index
    -- 7: Nested Iterator
    local current

    if state == -4 then
        return nil, nil
    end

    -- Initialise
    if state == 0 then
        nextContext = initialiseContext(context)
        state = setState(context, 3) -- signal to get (first) nested iterator
        context[5] = 1 -- set position to 1
    end

    while true do
        -- Grab next value from nested enumerator		
        if state == 4 then
            local childIterator = context[7]
            index, current = moveIterator(childIterator)
            if index ~= nil then
                return index, current
            else
                state = setState(context, 3)
            end
        end

        if state == 3 then
            local selector = context[4]
            local position = context[5]
            index = context[6]
            -- Get the next item from the iterator
            index, current = nextFunc(nextContext, index)
            if index ~= nil then
                -- Grab the child iterator via the selector function.
                local nestedObject = selector(current, position)
                assert(type(nestedObject) == 'table', 'Selected object must be a table.')
                context[5] = position + 1
                context[6] = index
                -- Setup the child iterator
                context[7] = { getIterator(nestedObject) }
                state = setState(context, 4)
            else
            	-- iterator doesn't have any more nested iterators.
                state = setState(context, -4)
                return nil, nil
            end
        end
    end
end

---Projects each element of a sequence and flattens the resulting sequences into one sequence.
---@param selector fun(item: any, position: integer): table
---@return Enumerator3
function Enumerator3:flatMap(selector)
    assert(selector, 'Selector cannot be nil')
    return Enumerator3.new(flatMapFunc, self.index, wrapContext2(self, selector, 0))
end


-- CONCAT
local concatFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: Second (collection/table)

    if state == -4 then
        return false
    end

	if state == 0 then
        nextContext = { getIterator(nextFunc, nextContext, index) }
		state = setState(context, 1)
	end

    while true do
        local current
        index, current = moveIterator(nextContext)
        if index ~= nil then
            context[3] = nextContext
            return index, current
        end

        -- Incremental state can be used to chain together infinite iterators instead of just 2.
        -- Though, currently only two are supported.
        state = setState(context, state + 1)
        if state > 2 then
            setState(context, -4)
            return nil, nil
        end
        nextContext = { getIterator(context[4]) }
    end
end

---Concatenates two sequences.
---@param second table
---@return Enumerator3
function Enumerator3:concat(second)
	assert(second, 'Second cannot be nil')
    return Enumerator3.new(concatFunc, self.index, wrapContext1(self, second))
end


-- APPEND
local appendFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: Item
    -- 5: ItemIndex
    -- 6: Append / Prepend

    -- This state is used for returning the prepend item as well as
    -- initialising the iterator.
    if state == 0 then
        -- Iterator gets wrapped so the index is stored locally.
        nextContext = { getIterator(nextFunc, nextContext, index) }
        context[3] = nextContext
        state = setState(context, 1)

        local append = context[6]
        if append == false then
            local item, itemIndex = context[4], context[5]
            return itemIndex, item
        end
    end

    if state == 1 then
        local current
        index, current = moveIterator(nextContext)
        if index ~= nil then
            return index, current
        else
            state = setState(context, -4)
        end

        local item, itemIndex = context[4], context[5]
        local append = context[6]
        if append == true then
            return itemIndex, item
        end
    end

    return nil, nil
end

---Appends a value to the end of the sequence.
---@param item any
---@param index? any
---@return Enumerator3
function Enumerator3:append(item, index)
    if index == nil then index = 'nil' end -- Index needs *some* value

    return Enumerator3.new(appendFunc, self.index, wrapContextN(self, item, index, true))
end

---Prepends a value to the start of the sequence.
---@param item any
---@param index? any
---@return Enumerator3
function Enumerator3:prepend(item, index)
    if index == nil then index = 'nil' end -- Index needs *some* value

    return Enumerator3.new(appendFunc, self.index, wrapContextN(self, item, index, false))
end


-- UNIQUE / DISTINCT
local uniqueFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    local keySelector = context[4]
    -- 5: Hashset for uniqueness
    local current

    if state == -4 then
        return false
    end

    if state == 0 then
        nextContext = initialiseContext(context)
        -- If we have any items, create a hashtable. Otherwise abort.
        -- We check this by moving to the next item in the iterator and checking
        -- if it's not nil. We then set the state to 1 which immediately uses the current/index
        -- without having to move to a new item.
        index, current = nextFunc(nextContext, index)
        if index ~= nil then
            context[5] = {}
            state = 1
        else
            setState(context, -4)
            return nil, nil
        end
    end

    -- State is only updated locally, because it is potentially set multiple times during one iteration.
    -- Persist state only when returned.
    local set = context[5]
    while true do
        -- Try to grab a new item.
        if state == 2 then
            index, current = nextFunc(nextContext, index)
            if index ~= nil then
                state = 1
            else
                setState(context, -4)
                return nil, nil
            end
        end

        if state == 1 then
            state = 2
            local key = keySelector and keySelector(current, index) or current
            if addToSet(set, key) == true then
                setState(context, state)
                return index, current
            end
        end
    end
end

---Returns unique (distinct) elements from a sequence according to a specified key selector function.
---@param keySelector? fun(current: any, index: any): any
---@return Enumerator3 
function Enumerator3:unique(keySelector)
    return Enumerator3.new(uniqueFunc, self.index, wrapContext1(self, keySelector))
end


-- DIFFERENCE
local differenceFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: Second collection
    local keySelector = context[5]
    -- 6: Hashset for uniqueness
    local current

    if state ~= 0 then
        if state ~= 1 then
            return nil, nil
        end
    else
        nextContext = initialiseContext(context)
        context[6] = Enumerator3.toSet(context[4], keySelector)
        setState(context, 1)
    end

    local set = context[6]
    while true do
        index, current = nextFunc(nextContext, index)
        if index ~= nil then
            local key = keySelector and keySelector(current, index) or current
            if addToSet(set, key) == true then
                return index, current
            end
        else
            setState(context, -4)
            return nil, nil
        end
    end
end

---Produces the set difference of two sequences according to a specified key selector function.
---@param second table
---@param keySelector? fun(current: any, index: any): any
---@return Enumerator3 
function Enumerator3:difference(second, keySelector)
    assert(second, 'Second collection cannot be nil.')

    return Enumerator3.new(differenceFunc, self.index, wrapContext2(self, second, keySelector))
end


-- UNION
local unionFunc = function (context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: Second collection
    local keySelector = context[5]
    -- 6: Hashset for uniqueness
    local current

    if state ~= 0 then
        if state ~= 1 then
            return nil, nil
        end
    else
        nextContext = { getIterator(nextFunc, nextContext, index) }
        context[3] = nextContext
        context[6] = {}
        state = setState(context, 1)
    end

    local set = context[6]
    while state > 0 do
        -- Iteration state (exhaust the current iterator)
        while true do
            index, current = moveIterator(nextContext)
            if index == nil then break end

            local key = keySelector and keySelector(current, index) or current
            if addToSet(set, key) == true then
                return index, current
            end
        end

        -- If the state is 2 at this point, the second iterator has 
        -- already been initialised and exhausted.
        if state == 2 then
            setState(context, -4)
            return nil, nil
        end

        -- Grab second iterator, first one is empty
        nextContext = { getIterator(context[4]) }
        context[3] = nextContext
        state = setState(context, 2)
    end
end

---Produces the set union of two sequences according to a specified key selector function.
---@param second table
---@param keySelector? fun(current: any, index: any): any
---@return Enumerator3
function Enumerator3:union(second, keySelector)
    assert(second, 'Second collection cannot be nil.')

    return Enumerator3.new(unionFunc, self.index, wrapContext2(self, second, keySelector))
end

-- INTERSECT
local intersectFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: Second collection
    local keySelector = context[5]
    -- 6: Hashset for uniqueness
    local current

    if state ~= 0 then
        if state ~= 1 then
            return nil, nil
        end
    else
        nextContext = initialiseContext(context)
        context[6] = Enumerator3.toSet(context[4], keySelector)
        state = setState(context, 1)
    end

    local set = context[6]
    while true do
        index, current = nextFunc(nextContext, index)
        if index == nil then
            setState(context, -4)
            return nil, nil
        end

        local key = keySelector and keySelector(current, index) or current
        if removeFromSet(set, key) == true then
            return index, current
        end
    end
end

---Produces the set intersection of two sequences according to a specified key selector function.
---@param second table
---@param keySelector? fun(current: any, index: any): any
function Enumerator3:intersect(second, keySelector)
    assert(second, 'Second collection cannot be nil.')

    return Enumerator3.new(intersectFunc, self.index, wrapContext2(self, second, keySelector))
end


-- ZIP
local zipFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: Second collection
    local resultSelector = context[5]

    if state ~= 0 then
        if state ~= 1 then
            return nil, nil
        end
    else
        -- First iterator gets stored in context, second in context[4]
        nextContext = initialiseContext(context)
        context[4] = { getIterator(context[4]) }
        state = setState(context, 1)
    end

    local second = context[4]
    local indexA, currentA = nextFunc(nextContext, index)
    local indexB, currentB = moveIterator(second)

    if indexA ~= nil and indexB ~= nil then
        local result = resultSelector and resultSelector(currentA, currentB) or { currentA, currentB }
        return indexA, result
    end

    setState(context, -4)
    return nil, nil
end

---Applies a specified function to the corresponding elements of two sequences, producing a sequence of the results.
---@param second table
---@param resultSelector? fun(itema: any, itemb: any): any
---@return Enumerator3
function Enumerator3:zip(second, resultSelector)
    assert(second, 'Second collection cannot be nil.')

    return Enumerator3.new(zipFunc, self.index, wrapContext2(self, second, resultSelector))
end


-- GROUPBY / GROUPBYRESULT
local groupByFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: keySelector
    -- 5: elementSelector
    local resultSelector = context[6]

    if state ~= 0 then
        if state ~= 1 then
            return nil, nil
        end
    else
        -- Pack iterator info into a structure getIterator recognises
        local iterator = { nextFunc, nextContext, index, _isIterator = true }

        local keySelector = context[4]
        local elementSelector = context[5]
        local lookup = Enumerator3.toLookup(iterator, keySelector, elementSelector)

        -- Overwrite iterator with new iterator.
        nextFunc, nextContext, index = getIterator(lookup)
        context[2] = nextFunc
        context[3] = nextContext
        state = setState(context, 1)
    end

    local key, elements = nextFunc(nextContext, index)
    if key ~= nil then
        local result = resultSelector and resultSelector(key, elements) or elements
        return key, result
    end

    setState(context, -4)
    return nil, nil
end

---Groups the elements of a sequence.
---@param keySelector fun(param: any): any
---@param elementSelector? fun(param: any): any
---@return Enumerator3
function Enumerator3:groupBy(keySelector, elementSelector)
    assert(keySelector, 'Key Selector cannot be nil.')

    return Enumerator3.new(groupByFunc, self.index, wrapContext2(self, keySelector, elementSelector))
end

function Enumerator3:groupByResult(keySelector, elementSelector, resultSelector)
    assert(keySelector, 'Key Selector cannot be nil.')
    assert(resultSelector, 'Result Selctor cannot be nil.')

    return Enumerator3.new(groupByFunc, self.index, wrapContextN(self, keySelector, elementSelector, resultSelector))
end

-- SORTING
-- This function is verbose on purpose. It is beneficial to spend more time returning a sort function
-- than create a sort function that has to make additional checks besides sorting.
local getSortFunction = function(sortSelectors)
    -- Special case where sort isn't chained.
    if #sortSelectors == 1 then
        local sortSelector = sortSelectors[1]
        local acendingSort = sortSelector[1]
        local sortSelector = sortSelector[2]
        if sortSelector ~= nil then
            if acendingSort == true then
                return function(a, b) return sortSelector(a) < sortSelector(b) end
            else
                return function(a, b) return sortSelector(a) > sortSelector(b) end
            end
        else
            if acendingSort == true then
                return function(a, b) return a < b end
            else
                return function(a, b) return a > b end
            end
        end
    end

    -- Return chained sorting.
    return function(a, b)
		for _, sortSelector in pairs(sortSelectors) do
			local selector = sortSelector[2]
			local sortAscending = sortSelector[1]

			local leftVal = selector(a)
			local rightVal = selector(b)
			if leftVal ~= rightVal then
				if sortAscending then
					return leftVal < rightVal
				else
					return leftVal > rightVal
				end
			end
		end
	end
end

local sortFunc = function(context, index)
    local state = context[1]
    local nextFunc = context[2]
    local nextContext = context[3]
    -- 4: sort selectors
    local current

    if state ~= 0 then
        if state ~= 1 then
            return nil, nil
        end
    else
        -- Create and sort buffer.
        nextContext = initialiseContext(context)
        local buffer = {}
        for _, value in nextFunc, nextContext, index do
            table.insert(buffer, value)
        end

        local sortFunc = getSortFunction(context[4])
        table.sort(buffer, sortFunc)

        nextFunc, nextContext, index = getIterator(buffer)
        context[2] = nextFunc
        context[3] = nextContext
        setState(context, 1)
    end

    index, current = nextFunc(nextContext, index)
    if index ~= nil then
        return index, current
    end

    setState(context, -4)
    return nil, nil
end

---Boilerplate function to setup various sorting Enumerator3
---@param self Enumerator3
---@param isDecending boolean
---@param selector? fun(current: any): any
---@return Enumerator3
local function getSorter(self, isDecending, selector)
    local selectors = { { isDecending, selector } }
    return Enumerator3.new(sortFunc, self.index, wrapContext1(self, selectors))
end

---Boilerplate function to chain one sort to the previous
---@param self table
---@param isDecending any
---@param selector any
local function getChainedSorter(self, isDecending, selector)
    assert(self.nextFunc == sortFunc, 'Previous function must be a "sort" or "order" variant.')

    -- Since the context isn't accessible for the child, we unwrap the context first by calling the factory
    -- we can then access the context to add a new sortselector to it.
    local selectors = self.contextFactory()[4]
    table.insert(selectors, { isDecending, selector })

    -- Wrap context into a factory again.
    self.contextFactory = wrapContext1(self, selectors)
    return self
end

function Enumerator3:sort()
    return getSorter(self, true)
end

function Enumerator3:sortDescending()
    return getSorter(self, false)
end

function Enumerator3:sortBy(selector)
    return getSorter(self, true, selector)
end

function Enumerator3:sortByDescending(selector)
    return getSorter(self, false, selector)
end

function Enumerator3:thenBy(selector)
    return getChainedSorter(self, true, selector)
end

function Enumerator3:thenByDecending(selector)
    return getChainedSorter(self, false, selector)
end

--------------------------------------------------------------------------------
-- Equality functions
--------------------------------------------------------------------------------
local equals = function(a, b)
    -- Start with a quick Lua equals comparison
    local result = a == b
    if result then
        return true
    end

    -- If this is false, we check for additional equality, such as sequence equality.
    local atype = type(a)
    local btype = type(b)
    if atype ~= btype then
        return false
    end

    if atype == 'table' then
        return Enumerator3.sequenceEquals(a, b)
    else
        return result
    end
end

---comment
---@param self Enumerator3
---@param item any
---@param comparer? fun(a: any, b: any): boolean
---@return integer
function Enumerator3.indexOf(self, item, comparer)
    local index = 1
    local cmp = comparer or equals
    for _, v in getIterator(self) do
        if cmp(v, item) == true then
            return index
        end
        index = index + 1
    end
    return -1
end

---Determines whether the sequence contains the provided item according to an equality comparer.
---@param self table
---@param item any
---@param comparer? fun(a: any, b: any): boolean
---@return boolean
function Enumerator3.contains(self, item, comparer)
    local cmp = comparer or equals
    for _, v in getIterator(self) do
        if cmp(v, item) == true then
            return true
        end
    end
    return false
end

---Determines whether two sequences are equal according to an equality comparer.
---@param self table
---@param other table
---@param comparer? fun(a: any, b: any): boolean
---@return boolean
function Enumerator3.sequenceEquals(self, other, comparer)
    local cmp = comparer or equals

    local next, context, index, current = getIterator(other)

    for _, v in getIterator(self) do
        index, current = next(context, index)
        if cmp(v, current) == false then
            return false
        end
    end

    -- We have exhausted the first iterator. For the sequences to be equal, the second iterator also
    -- has to be exhausted. We know this is the case if the last returned index is also nil.
    return index == nil
end

--------------------------------------------------------------------------------
-- Sequence search functions
--------------------------------------------------------------------------------
local function getFirstItem(self, defaultValue)
    local firstItem = nil

    local nextFunc, context, index = getIterator(self)
    -- Shortcut for arrays
    if nextFunc == ipairsFunc then
        firstItem = context[1]
    else
        _, firstItem = nextFunc(context, index)
    end

    return firstItem or defaultValue
end

local function getLastItem(self, defaultValue)
    local nextFunc, context, index = getIterator(self)
    local lastItem = nil

    if nextFunc == ipairsFunc then
        lastItem = context[#context]
    else
        -- Run iterator to the end
        local k, v = index, _
        repeat
            k, v = nextFunc(context, k)
        until k == nil
        lastItem = v
    end

    return lastItem or defaultValue
end

---Returns the first item in the sequence, or a default value if there are no items in the sequence.
---@param self table
---@param predicate? fun(value: any, key: any): boolean
---@param defaultValue? any
---@return any
function Enumerator3.firstOrDefault(self, predicate, defaultValue)
    if predicate == nil then
        return getFirstItem(self, defaultValue)
    end

    local nextFunc, context, index = getIterator(self)
    for k, v in nextFunc, context, index do
        if predicate(v, k) == true then
            return v
        end
    end

    return defaultValue
end

---Returns the first item in the sequence, or an error if there are no items in the sequence.
---@param self table
---@param predicate? fun(value: any, key: any): boolean
---@return any
function Enumerator3.first(self, predicate)
    local result = Enumerator3.firstOrDefault(self, predicate, nil)
    if result == nil then
        error('Sequence contains no (matching) elements.')
    else
        return result
    end
end

---Returns the last item in the sequence, or a default value if there are no items in the sequence.
---@param self table
---@param predicate? fun(value: any, key: any): boolean
---@param defaultValue? any
---@return any
function Enumerator3.lastOrDefault(self, predicate, defaultValue)
    if predicate == nil then
        return getLastItem(self, defaultValue)
    end

    local nextFunc, context, index = getIterator(self)
    local lastMatch = nil
    for k, v in nextFunc, context, index do
        if predicate(v, k) == true then
            lastMatch = v
        end
    end

    return lastMatch or defaultValue
end

---Returns the last item in the sequence, or an error if there are no items in the sequence.
---@param self table
---@param predicate? fun(value: any, key: any): boolean
---@return any
function Enumerator3.last(self, predicate)
    local result = Enumerator3.lastOrDefault(self, predicate, nil)
    if result == nil then
        error('Sequence contains no (matching) elements.')
    else
        return result
    end
end

---Returns the length of this collection.
---@param self table
---@return integer
function Enumerator3.count(self)
    local nextFunc, context, index = getIterator(self)
    -- Shortcut for arrays
    if nextFunc == ipairsFunc then
        return #context
    end

    local len = 0
    for _, _ in nextFunc, context, index do
        len = len + 1
    end
    return len
end

---Returns the number of elements in a sequence that match a predicate.
---@param self Enumerator3
---@param predicate fun(value: any, key: any): any
---@return integer
function Enumerator3.countBy(self, predicate)
    assert(predicate, 'Predicate cannot be nil.')
    local count = 0
    for k, v in getIterator(self) do
        if predicate(v, k) == true then
            count = count + 1
        end
    end
    return count
end

--- Determines whether all elements of a sequence satisfy a condition.
---@param self Enumerator3
---@param predicate fun(current: any, index: any): boolean
---@return boolean
function Enumerator3.all(self, predicate)
    assert(predicate)
    for key, value in getIterator(self) do
        if predicate(value, key) == false then
            return false
        end
    end
    return true
end

---Determines whether any element of a sequence exists or satisfies a condition.
---@param self Enumerator3
---@param predicate? fun(current: any, index: any): boolean
---@return boolean
function Enumerator3.any(self, predicate)
    local nextFunc, context, index = getIterator(self)
    -- Check without predicate (just need a first item to exist)
    if predicate == nil then
        -- Array shortcut.
        if nextFunc == ipairsFunc then
            return #context > 0
        else
            -- Check if we can iterate once.
            local inx, _ = nextFunc(context, index)
            return inx ~= nil
        end
    -- Check with a predicate. We need one item that matches the predicate.
    else
        for key, value in nextFunc, context, index do
            if predicate(value, key) == true then
                return true
            end
        end
    end

    return false
end

--------------------------------------------------------------------------------
-- Iteration via function
--------------------------------------------------------------------------------
function Enumerator3.foreach(self, func)
    assert(type(func) == 'function')

    for _, current in getIterator(self) do
        func(current)
    end
    return nil
end

function Enumerator3.ipairs(self)
    return getIterator(self)
end

function Enumerator3.pairs(self)
    return getIterator(self)
end

--------------------------------------------------------------------------------
-- Reduction
--------------------------------------------------------------------------------

---Applies an accumulator function over a sequence. The specified seed value is used as the initial accumulator value, and the specified function is used to select the result value.
---@param self table
---@param func fun(accumulate: any, next: any): any
---@param seed? any
---@param resultSelector? fun(result: any): any
---@return any
function Enumerator3.aggregate(self, func, seed, resultSelector)
    assert(func, 'Aggregate function cannot be nil.')

    local result = seed
    local next, context, index = getIterator(self)

    -- We need a starting element.
    if result == nil then
        index, result = next(context, index)
        if index == nil then
            error('Sequence contains no elements')
        end
    end

    for _, current in next, context, index do
        result = func(result, current)
    end

    if resultSelector ~= nil then
        result = resultSelector(result)
    end

    return result
end

--------------------------------------------------------------------------------
-- Arithmetic functions
--------------------------------------------------------------------------------
local maxCmp = function(a, b)
    if a < b then return true end
end

local minCmp = function(a, b)
    if a > b then return true end
end

local minmaxBy = function(self, selector, comparison)
    local nextFunc, context, index = getIterator(self)

    -- Grab the first item
    local key, value = nextFunc(context, index)
    local maxVal = selector(value, key)
    local maxItem = value

    local curr = nil
    for k, v in nextFunc, context, key do
        curr = selector(v, k)
        if comparison(maxVal, curr) == true then
            maxVal = curr
            maxItem = v
        end
    end

    return maxItem
end

local minmax = function(self, comparison)
    local nextFunc, context, index = getIterator(self)

    -- Grab the first item
    local key, value = nextFunc(context, index)
    local maxVal = value

    for _, v in nextFunc, context, key do
        if comparison(maxVal, v) == true then
            maxVal = v
        end
    end

    return maxVal
end

---Returns the maximum value in a sequence of values.
---@param self Enumerator3
---@return number
function Enumerator3.max(self)
    return minmax(self, maxCmp)
end

---Returns the item with the highest value in a sequence.
---@param self Enumerator3
---@param selector fun(item: any, index: any): number
---@return unknown
function Enumerator3.maxBy(self, selector)
    assert(selector)
    return minmaxBy(self, selector, maxCmp)
end

---Returns the minimum value in a sequence of values.
---@param self Enumerator3
---@return number
function Enumerator3.min(self)
    return minmax(self, minCmp)
end

---Returns the item with the lowest value in a sequence.
---@param self Enumerator3
---@param selector fun(item: any, index: any): number
---@return unknown
function Enumerator3.minBy(self, selector)
    assert(selector)
    return minmaxBy(self, selector, minCmp)
end

---Returns the sum value of a sequence of values.
---@param self Enumerator3
---@return number
function Enumerator3.sum(self)
    local total = 0
    for _, v in getIterator(self) do
        total = total + v
    end
    return total
end

--------------------------------------------------------------------------------
-- Enumerator functions that result in a new collection.
--------------------------------------------------------------------------------

---Creates a set from a table|Enumerator3 with a specified key for uniqueness.
---@param self table
---@param keySelector? fun(current:any, index: any): any
---@return table
function Enumerator3.toSet(self, keySelector)
    local set = {}
    for inx, current in getIterator(self) do
        if keySelector == nil then
            set[current] = true
        else
            local key = keySelector(current, inx)
            set[key] = true
        end
    end
    return set
end

---Creates an array from a table|Enumerator3
---@param self table
---@return table
function Enumerator3.toTable(self)
    local tab = {}
    for _, value in getIterator(self) do
        table.insert(tab, value)
    end
    return tab
end

---Creates a lookup from a table|Enumerator3
---This is a { key, { elements } } structure
---@param self table
---@return table
function Enumerator3.toLookup(self, keySelector, elementSelector)
    local lookup = {}

    for inx, value in getIterator(self) do
        -- Retrieve grouping by key
        local key = keySelector(value, inx)
        assert(key, 'Key cannot be nil.')
        local grouping = lookup[key]

        -- Create new grouping if it doesn't exist.
        if grouping == nil then
            grouping = {}
            lookup[key] = grouping
        end

        -- Add element to grouping
        local element = elementSelector and elementSelector(value, inx) or value
        table.insert(grouping, element)
    end

    return lookup
end

---Creates a dictionary (key, value) structure based on a keyselector and an elementselector
---@param self Enumerator3
---@param keySelector? fun(value: any, key: any): any
---@param elementSelector? fun(value: any, key: any): any
---@return table
function Enumerator3.toDictionary(self, keySelector, elementSelector)
    local dictionary = {}

    for key, value in getIterator(self) do
        if keySelector ~= nil then
            key = keySelector(value, key)
        end
        if elementSelector ~= nil then
            value = elementSelector(value, key)
        end

        dictionary[key] = value
    end
    return dictionary
end

---Creates a deep copy of the provided object.
---@param self any
---@return any
function Enumerator3.deepCopy(self)
    local orig_type = type(self)
    local copy
    if orig_type == 'table' then
        copy = {}
        for k, v in getIterator(self) do
            copy[Enumerator3.deepCopy(k)] = Enumerator3.deepCopy(v)
        end
    else
        copy = self
    end
    return copy
end

--------------------------------------------------------------------------------
-- Function aliasses
--------------------------------------------------------------------------------
Enumerator3.select = Enumerator3.map
Enumerator3.selectMany = Enumerator3.flatMap
Enumerator3.distinct = Enumerator3.unique
Enumerator3.except = Enumerator3.difference
Enumerator3.order = Enumerator3.sort
Enumerator3.orderDecending = Enumerator3.sortDescending
Enumerator3.orderBy = Enumerator3.sortBy
Enumerator3.orderByDecending = Enumerator3.sortByDescending

Enumerator3.each = Enumerator3.foreach
Enumerator3.for_each = Enumerator3.foreach
Enumerator3.length = Enumerator3.count
Enumerator3.lengthBy = Enumerator3.countBy
Enumerator3.has = Enumerator3.contains
Enumerator3.fold = Enumerator3.aggregate
Enumerator3.reduce = Enumerator3.aggregate

return Enumerator3
