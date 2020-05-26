
import json, tables, sequtils, algorithm, times

type
  SObjState* = enum
    new, dirty, synched

# wrap json data for easier handling
type
  StoreObj* = object
    id*:  string
    `type`*: string
    data*: JsonNode # use nim root obj (?)
    state*: SObjState
      
  ObjCollection = object
    current: string # id
    `type`: string
    ids: seq[string] # ids
  
  Store* = object
    data*: Table[string, StoreObj] # id, obj
    collection: Table[string, ObjCollection] # type, Storecollection
      
proc newStore*(): Store =
  result =  Store()
  result.data = initTable[string, StoreObj]()
  result.collection = initTable[string, ObjCollection]()
  
proc hasKey*(store: Store, key: string): bool =
  result = store.collection.haskey key
  
proc getItem*(store: Store, id: string): StoreObj =
  result = store.data[id]

proc add*(store: var Store, so: StoreObj) =
  # TODO: warn when an object cannot be added
  # (no id, etc)
  if not store.collection.haskey so.`type`:
    store.collection[so.`type`] = ObjCollection(`type`: so.`type`)
    store.collection[so.`type`].ids = @[]
  store.collection[so.`type`].ids.add so.id
  store.data[so.id] = so

proc add*(store: var Store, objType: string, obj: JsonNode) =
  # TODO: warn when an object cannot be added
  # (no id, etc)
  var so = StoreObj()
  so.id = obj["id"].getStr
  so.`type` = objType
  so.data = obj
  store.add so

proc getItemByField*(store: Store, objType, field: string, value: JsonNode): StoreObj =
  var r: StoreObj
  var cmpr = proc(id: string , val: JsonNode): int {.closure.} =
    let obj = store.getItem id
    if obj.data.haskey(field) and obj.data[field] == val:
      r = obj
      result = 0
    else:
      result = -1
  let exists = binarySearch(store.collection[objType].ids, value, cmpr)
  if exists == 0: result = r

proc getCurrent*(store: Store, objType: string): StoreObj =
  let cid = store.collection[objType].current
  if cid != "":
    result = getItem(store, cid)

proc getCollection*(store: Store, objType: string): seq[StoreObj] =
  result = @[]
  if store.collection.haskey objType:
    for id in store.collection[objType].ids:
      result.add store.data[id]

proc getItems*(store: Store, objType: string): seq[JsonNode] =
  result = @[]
  let collection = getCollection(store, objType)
  for item in collection:
    result.add item.data   

proc setCurrent*(store: var Store, oType="", id: string) =
  var objType = oType
  if objType == "":
      let c = store.getItem id
      objType = c.`type`
      
  if store.collection.hasKey objType:
    if objType != "":
      store.collection[objType].current = id
  else:
    store.collection[objType] = ObjCollection(current: id)

proc setFieldValue*(store: var Store, id, field: string, value: JsonNode) =
  store.data[id].data[field] = value

proc setOrCreateFieldValue*(store: var Store, objType, id, field: string, value: JsonNode) =
  if not store.data.haskey id:
     store.add StoreObj(id: id, `type`: objType, state: SObjState.new, data: %{field: value})
  else:
    store.setFieldValue(id, field, value)     

proc getFieldValue*(store: var Store, id, field: string): JsonNode =
  if store.data.hasKey(id) and store.data[id].data.hasKey(field):
    result = store.data[id].data[field]

proc delete*(store: var Store, id: string) =
  # remove from lists
  # remove object
  echo "deleting access token"
  let
    obj = store.getItem(id)
    objType = obj.`type`
    indx = store.collection[objType].ids.find id
  delete(store.collection[objType].ids, indx, indx+1)
  store.data.del id
  echo store.collection[objType].ids.len
  
  if store.collection[objType].ids.len == 0:
    store.collection.del objType

proc hasItem*(store: Store, id: string): bool =
  result = store.data.hasKey id
  
