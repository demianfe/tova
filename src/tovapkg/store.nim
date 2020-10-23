
import json, tables, sequtils, algorithm, times, strformat

## --- uuid ------
import jsffi
proc genUUID*(): string =
  result = ""
  proc random(): float {.importc: "Math.random".}
  proc floor(n: float): int8 {.importcpp: "Math.floor(#)".}
  for i in 0..35:
    const adigits = "0123456789abcdef"
    case i:
      of 8, 13, 18, 23:
        result &= "-"
      of 14:
        result &= "4"
      else:
        var r = random() * 16
        result &= adigits[floor(r)]  
## -- end uuid

type
  SObjState* = enum
    new, dirty, sync

# wrap json data for easier handling
type
  StoreObj* = object
    id:  string
    model*: string
    data*: JsonNode
    state: SObjState
      
  ObjCollection = object
    current: string # id
    model: string
    ids: seq[string] # ids
  
  Store* = object
    data*: Table[string, StoreObj] # id, obj
    collection: Table[string, ObjCollection] # type, Storecollection
    
proc newStore*(): Store =
  result = Store()
  result.data = initTable[string, StoreObj]()
  result.collection = initTable[string, ObjCollection]()

proc newStoreObj*(): StoreObj =
  result = StoreObj(id: genUUID(), state: SObjState.new)

proc newStoreObj*(so: StoreObj): StoreObj =
  result = so
  result.id = genUUID()
  
proc newStoreObj*(model: string, state: SObjState, data: JsonNode): StoreObj =
  result = StoreObj(id: genUUID(), model: model, state: state, data: data)

proc id*(so: StoreObj): string =
  result = so.id
  
proc hasKey*(store: Store, key: string): bool =
  result = store.collection.haskey key
  
proc getItem*(store: Store, id: string): StoreObj=
  result = store.data[id]

proc add*(store: var Store, so: StoreObj) =
  # TODO: warn when an object cannot be added
  # (no id, etc)
  if not store.collection.haskey so.model:
    store.collection[so.model] = ObjCollection(model: so.model)
    store.collection[so.model].ids = @[]
  store.collection[so.model].ids.add so.id
  store.data[so.id] = so

proc add*(store: var Store, model: string, data: JsonNode) =
  # TODO: warn when an object cannot be added
  # (no id, etc)
  var so = newStoreObj()
  so.model = model
  so.data = data
  so.state = SObjState.sync
  store.add so

proc addAll*(store: var Store, model: string, obj: JsonNode) =
  if obj.kind == JArray:
    for o in obj.items:
      store.add(model, o)

proc getItemByField*(store: Store, model, field: string, value: JsonNode): StoreObj {.deprecated.} =
  var r: StoreObj
  var cmpr = proc(id: string , val: JsonNode): int {.closure.} =
    let obj = store.getItem id
    if obj.data.haskey(field) and obj.data[field] == val:
      r = obj
      result = 0
    else:
      result = -1
  let exists = binarySearch(store.collection[model].ids, value, cmpr)
  if exists == 0: result = r

proc getCollection*(store: Store, model: string): seq[StoreObj] =
  result = @[]
  if store.collection.haskey model:
    for id in store.collection[model].ids:
      result.add store.data[id]

proc getItems*(store: Store, model: string): seq[JsonNode] =
  result = @[]
  let collection = getCollection(store, model)
  for item in collection:
    result.add item.data   

proc find*(store: Store, model, field: string, value: JsonNode): seq[StoreObj] =
  for id in store.collection[model].ids:
    let obj = store.getItem id
    if obj.data.haskey(field) and obj.data[field] == value:
      result.add obj  

proc filter*(store: Store, model: string, f: proc(item: StoreObj): bool): seq[StoreObj] =
  result = filter(store.getCollection(model), f)
    
proc setCurrent*(store: var Store, id: string) =
  let
    c = store.getItem id
    ot = c.model
  if store.collection.hasKey ot:
    store.collection[ot].current = id
  else:
    store.collection[ot] = ObjCollection(current: id)

proc getCurrent*(store: Store, model: string): StoreObj =
  if store.collection.haskey model:
    let cid = store.collection[model].current
    if cid != "":
      result = getItem(store, cid)

proc unsetCurrent*(store: var Store, ot: string) =
  if store.collection.haskey ot:
    store.collection[ot].current = ""

proc unsetCurrentId*(store: var Store, id: string) =
  let c = store.getItem id
  store.unsetCurrent c.model

proc addCurrent*(store: var Store, s: StoreObj) =
  #adds and sets as current
  store.add s
  store.setCurrent s.id
  
proc state*(so: StoreObj): SObjState =
  result = so.state

proc updateState*(store: var Store, id: string, state: SObjState) =
  var so = store.getItem id
  so.state = state
  store.data[id] = so
  
proc setFieldValue*(store: var Store, id, field: string, value: JsonNode) =
  if store.data.haskey id:
    store.data[id].data[field] = value
  else:
    echo fmt"WARNING: object with id: {id} not found in store."
    
# proc setOrCreateFieldValue*(store: var Store, model, id, field: string, value: JsonNode): string =
#   # returns the new id of the obj
#   if not store.data.haskey id:
#      store.add StoreObj(id: genUUID(), model: model, state: SObjState.new, data: %{field: value})
#   store.setFieldValue(id, field, value)

proc getFieldValue*(store: var Store, id, field: string): JsonNode =
  if store.data.hasKey(id) and store.data[id].data.hasKey(field):
    result = store.data[id].data[field]

proc delete*(store: var Store, id: string) =
  let
    obj = store.getItem(id)
    model = obj.model
    indx = store.collection[model].ids.find id
  store.unsetCurrentId(id=id)
  delete(store.collection[model].ids, indx, indx+1)
  store.data.del id  
  if store.collection[model].ids.len == 0:
    store.collection.del model

proc clear*(store: var Store, model: string) =
  # deletes everything for a given model
  if store.collection.haskey model:
    let ids = store.collection[model].ids
    for id in ids:
      store.delete id
  
proc hasItem*(store: Store, id: string): bool =
  result = store.data.hasKey id
  
