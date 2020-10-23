
when defined(js):
  import asyncjs
else:
  import asyncdispatch
  
import strutils, sequtils, tables, json, store, strformat
import karax / [vdom, karaxdsl, kdom]
include karax / prelude
import karax / prelude

import listeners

type
  MessageKind* = enum
    normal, success, warning, error, primary, danger
    
  AppMessage* = ref object
    id*: string
    title*: string
    content*: string
    kind*: MessageKind

  AppContext* = ref object of RootObj
    state*: JsonNode
    actions*: Table[cstring, proc(payload: JsonNode)]
    renderProcs*: seq[string]
    navigate*: proc(ctxt: var AppContext, payload: JsonNode, viewid: string): JsonNode # returns the new payload
    store*: Store
    queryString*: OrderedTable[string, string]
    route*: string
    messages*: seq[AppMessage]
    eventHandler*: proc(uiev: tova.UiEvent, el: UiElement, viewid: string): proc(ev: Event, n: VNode)
    eventsMap*: Table[tova.UiEventKind, EventKind]
    #render*: proc()
    kxi*: KaraxInstance
    location*: (string, string) # use window obj?
    # karax objects
    window*: Window 
    document*: Document
    navigator*: Navigator
    
  UiApp* = ref object
    id*: string
    title*: string
    layout*: proc(ctxt: AppContext): UiElement
    state*: string
    ctxt*: AppContext

  UiElementKind* = enum
    kUiElement, kLayout, kHeader, kFooter, kBody, kButton, kDropdopwn, kIcon,
    kLabel, kText, kMenu, kMenuItem, kNavbar, kNavSection, kLink, kInputText,
    kList, kListItem, kForm, kCheckBox, kDropdown, kDropdownItem, kPanel, kTile,
    kTable, kColumn, kRow, kRadio, kRadioGroup, kParagraph, kTitle,kBreadcrum,
    kItem, kHero, kMessage, kLoading, kDiv, kHr

  UiElement* = ref UiElementObj

  UiEventKind* = enum
    click, keydown, keyup, change
    
  UiEvent* = object
    kind*: UiEventKind
    targetKind*: EventKind # karax event
    handler*: string # a key in the actions table
    
  UiElementObj = object
    elid: string
    parentId: string
    id*: string
    viewid*: string
    kind*: UiElementKind # kUiExolement for generic or custom elements
    label*: string # what is to be shown as label
    value*: string # the value of the field
    model*: string # the object model the fields maps to
    field*: string # the field of the entity
    attributes*: Table[string, string]
    kids: seq[UiElement]
    events*: seq[UiEvent]
    builder*: proc(el: UiElement): Vnode
    ctxt*: AppContext
    preventDefault*: bool

proc render*(ctxt: AppContext) =
  ctxt.kxi.redraw()
    
var pid = 0
template genId*: untyped =
  inc(pid)
  pid

proc setElid(el: var UiElement, parent: UiElement = nil) =
  if parent != nil:
    el.elid = $parent.elid & "." & $parent.kids.len
    el.parentId = parent.elid
  else:
    el.elid = $0

proc add*(parent: var UiElement, child: UiElement) =
  var c = child
  c.setElid(parent)
  parent.kids.add c
  
proc add*(parent: var UiElement, children: openArray[UiElement]) =
  for c in children:
    parent.add c

proc addChild*(parent: var UiElement, child: UiElement) =
  parent.add child

proc `children=`*(parent: UiElement, kids: openArray[UiElement]) =
  parent.kids = @kids
  
proc children*(parent: UiElement): seq[UiElement] =
  result = parent.kids

proc `$`*(el: UiElement): string =
  result = ""
  result.add "\nelid: " & el.elid
  result.add "\nparentid: " & el.parentId
  result.add "\nid: " & el.id
  result.add "\nkind: " & $el.kind
  result.add "\nlabel: " & el.label
  result.add "\nvalue: " & el.value
  result.add "\nAttributes:" & $el.attributes
  result.add "\nEvents:" & $el.events
  result.add "\nChildren:"
  for c in el.children:
    result.add " " & $c.kind

proc `$`*(ctxt: AppContext): string =
  result = ""
  result.add "\nstate" & $ctxt.state
  result.add "\nqueryString " & $ctxt.queryString
  result.add "\nroute" & $ctxt.route
  result.add "\neventsMap " & $ctxt.eventsMap
  
proc elid*(el: UiElement): string =
  el.elid  

proc hasAttr(n: Vnode, at, val: kstring): bool =
  for attr in n.attrs:
    if attr == (at, val):
      result = true
      break
  
proc mergeEvents*(n: var Vnode, el: UiElement) =
  # check that the event wasnt already added
  let ctxt = el.ctxt
  if not ctxt.isNil:
    for ev in el.events:
      if ev.handler != "" and not n.hasAttr("eventhandler", ev.handler):
        let targetKind = ctxt.eventsMap[ev.kind]
        n.setAttr("eventhandler", ev.handler)
        let eh = ctxt.eventHandler(ev, el, el.viewid)
        n.addEventListener(targetKind, eh)

proc addEvents*(n: var Vnode, el: UiElement) =
  # Extracts events from the uielement and adds it
  # to the low level component.
  let ctxt = el.ctxt
  if not ctxt.isNil:
    for ev in el.events:
      let targetKind = ctxt.eventsMap[ev.kind]
      n.setAttr("eventhandler", ev.handler)
      let eh = ctxt.eventHandler(ev, el, el.viewid)
      n.addEventListener(targetKind, eh)
  else:
    echo "No context for UiElement"
    echo el
      
proc addAttributes*(n: var Vnode, el: UiElement) =
  # Merges the attribute using low level component
  if el.id!="": n.id = el.id
  if el.value != "":
    n.setAttr "value", el.value
  for k, v in el.attributes.pairs:
    var attrVal = n.getAttr k
    if attrVal == "" or attrVal == "null":
      attrVal = attrVal & " " & v
    else:
      attrVal = v
    n.setAttr(k, attrVal)
    
proc hasAttribute*(el: UiElement, attr: string): bool =
  result = el.attributes.haskey attr  

proc getAttribute*(el: UiElement, key: string): string =
  if el.hasAttribute key:
    result = el.attributes[key]
  
proc setAttribute*(parent: var UiElement, key, value: string) =
  parent.attributes[key] = value

proc mergeAttribute*(parent: var UiElement, key, value: string) =
  # merges with current attribute
  var newVal = value
  if parent.attributes.haskey(key) and parent.attributes[key] != "":
    newVal = parent.attributes[key] & " " & value
  parent.attributes[key] = newVal 

proc removeAttribute*(parent: var UiElement, key: string) =
  if parent.attributes.haskey(key):
    parent.attributes.del key

proc addEvent*(parent: var UiElement, event: UiEvent) =
  ## if it does not exist it is added
  # remove the event and add it again
  var
    indx = 0
    rm = false
  for e in parent.events:
    if event.kind == e.kind:
      rm = true
      break
    indx += 1
  if rm == true: parent.events.delete indx
  parent.events.add event

proc newUiElement*(): UiElement =
  result = UiElement()
  result.elid = $genId()
  result.kind = UiElementKind.kUiElement
  
proc newUiElement*(kind: UiElementKind): UiElement =
  result = newUiElement()
  result.kind = kind

proc newUiElement*(kind: UiElementKind, id, label: string): UiElement =
  result = newUiElement()
  result.kind = kind
  if label != "":
    result.label = label     
  if id != "":
    result.id = id
  
proc addEvent*(e: var UiElement, evk: UiEventKind) =
  var ev = UiEvent()
  ev.kind = evk
  e.events.add ev
    
proc newUiElement*(ctxt: AppContext): UiElement =
  result = UiElement()
  result.ctxt = ctxt
  result.elid = $genId()

proc newUiElement*(ctxt: AppContext, class: string): UiElement =
  result = newUiElement(ctxt)
  result.setAttribute("class", class)
  
proc newUiElement*(ctxt: AppContext, kind: UiElementKind): UiElement =
  result = newUiElement(ctxt)
  result.kind = kind

proc newUiElement*(ctxt: AppContext, kind: UiElementKind, id, label: string): UiElement =
  result = newUiElement(ctxt)
  result.kind = kind
  if label != "":
    result.label = label     
  if id != "":
    result.id = id
    
proc newUiElement*(ctxt: AppContext, kind: UiElementKind, id, label="", events: seq[UiEventKind]): UiElement =
  result = newUiElement(ctxt, kind)
  if label != "":
    result.label = label

  if id != "":
    result.id = id
  for evk in events:
    var ev = UiEvent()
    ev.kind = evk
    result.events.add ev
      
proc newUiElement*(ctxt: AppContext, kind: UiElementKind, label="",
                   attributes:Table[string, string], events: seq[UiEventKind]): UiElement =    
  result = newUiElement(ctxt, kind, label = label, events = events)
  result.kind = kind
  result.attributes = attributes    

proc newUiEvent*(k: UiEventKind, handler: string):UiEvent =
  result = UiEvent()
  result.kind = k
  result.handler = handler

# Messages
proc newMessage*(content: string, kind: MessageKind, title=""): AppMessage =
  result = AppMessage()
  result.content = content
  result.kind = kind
  result.title = title

proc newMessage*(content: string, title=""): AppMessage =
  result = newMessage(content, MessageKind.normal)
  result.title = title
  
proc newSuccessMessage*(content: string, title=""): AppMessage =
  result = newMessage(content, MessageKind.success)
  result.title = title
  
proc newWarningMessage*(content: string, title=""): AppMessage =
  result = newMessage(content, MessageKind.warning)
  result.title = title
  
proc newErrorMessage*(content: string, title=""): AppMessage =
  result = newMessage(content, MessageKind.error)
  result.title = title
  
proc newPrimaryMessage*(content: string, title=""): AppMessage =
  result = newMessage(content, MessageKind.primary)
  result.title = title
  
proc newDangerMessage*(content: string, title=""): AppMessage =
  result = newMessage(content, MessageKind.danger)
  result.title = title
  
proc addMessage*(ctxt: AppContext, kind: MessageKind, content: string,  title="") =
  var msg: AppMessage  
  case kind
  of MessageKind.success:
    msg = newSuccessMessage(content, title)
  of MessageKind.warning:
    msg = newWarningMessage(content, title)
  of MessageKind.error:
    msg = newErrorMessage(content, title)
  of MessageKind.primary:
    msg = newPrimaryMessage(content, title)
  of MessageKind.danger:
    msg = newDangerMessage(content, title)
  else:
    msg = newMessage(content, title)
  ctxt.messages.add msg

proc addMessage*(ctxt: AppContext, kind: string, content: string,  title="") {.deprecated.}=
  var msg: AppMessage  
  case kind
  of "success":
    msg = newSuccessMessage(content, title)
  of "warning":
    msg = newWarningMessage(content, title)
  of "error":
    msg = newErrorMessage(content, title)
  of "primary":
    msg = newPrimaryMessage(content, title)
  of "danger":
    msg = newDangerMessage(content, title)
  else:
    msg = newMessage(content, title)  
  ctxt.messages.add msg
  
proc addMessage*(ctxt: AppContext, m: AppMessage) =
  ctxt.messages.add m

proc noEventListener(payload: JsonNode, action: string): proc(payload: JsonNode) =
  result = proc(payload: JsonNode) =
    echo "WARNING: Action $1 not found in the table." % $action
  
proc callEventListener(payload: JsonNode,
                        actions: Table[cstring, proc(payload: JsonNode)]) =
  var eventListener: proc(payload: JsonNode)
  var a, model, tova_action: string
  
  let
    nodeKind = payload["node_kind"].getStr
    eventKind = payload["event_kind"].getStr.replace("on", "")
    defaultNodeAction = "default_action_" & nodeKind & "_" & eventKind
  
  if payload.haskey("eventhandler") and payload["eventhandler"].getStr != "":    
    tova_action = payload["eventhandler"].getStr
  else:
    if payload.haskey("model"):
      model = payload["model"].getStr
    if payload.haskey("action"):
      a = payload["action"].getStr
    elif payload.haskey("field"): # field
      a = payload["field"].getStr
      
    tova_action = "$1_$2_$3" % [model, a, eventKind]

  if actions.hasKey tova_action:
    eventListener = actions[tova_action]
  elif actions.hasKey defaultNodeAction:
    eventListener = actions[defaultNodeAction]
  elif actions.hasKey "tova_default_action":
    # default action
    eventListener = actions["tova_default_action"]
  else:
    eventListener = noEventListener(payload, tova_action)
  eventListener payload

proc makePayload*(ev: Event, n: VNode): JsonNode =
  result = %*{"value": %""}
             
  let evt = ev.`type`
  var event = %*{"type": %($evt)}

  for k, v in n.attrs:
    result[$k] = %($v)

  if not evt.isNil and evt.contains "key":
    event["keyCode"] = %(cast[KeyboardEvent](ev).keyCode)
    event["key"] = %($cast[KeyboardEvent](ev).key)

  result["event"] = event
  # if n.kind == VnodeKind.input:
  #   # colides with the input has a type
  #   result["type"] = %($n.getAttr "type")
  
  result["node_kind"] = %($n.kind)
      
  if n.getAttr("action") != nil:
    result["action"] = %($n.getAttr "action")
  if n.getAttr("mode") != nil:
    result["mode"] = %($n.getAttr "mode")
  if n.getAttr("name") != nil:
    result["field"] = %($n.getAttr "name")
  if n.getAttr("field") != nil:
    result["field"] = %($n.getAttr "field")

  if not n.value.isNil and n.value != "":
    result["value"] = %($n.value)
  if not n.id.isNil and n.id != "":
    result["id"] = %($n.id)
  
proc eventHandler(uiev: tova.UiEvent, el: UiElement, viewid: string): proc(ev: Event, n: VNode) =
  let ctxt = el.ctxt
  result = proc(ev: Event, n: VNode) =
    ev.preventDefault()
    var payload = makePayload(ev, n)
    
    payload["event_kind"] = %uiev.kind
    
    if el.id != "":
      payload["sid"] = %el.id

    if payload.haskey "action":
      callEventListener(payload, ctxt.actions)

    elif n.getAttr("eventhandler") != nil:
      let eh = $n.getAttr "eventhandler"
      payload["eventhandler"] = %(eh)
      callEventListener(payload, ctxt.actions)  
      if eh in el.ctxt.renderProcs:
        render(el.ctxt)

proc payload*(el: UiElement): JsonNode =
  result = %*{
    "id": el.id,
    "field": el.field,
    "label": el.label,
    "value": el.value,
    "kind": el.kind,
    "model": el.model
  }

proc dispatch*(el: UiElement, l: string) =
  if el.ctxt.actions.haskey l:
    let action = el.ctxt.actions[l]
    action(el.payload)
  else:
    echo fmt"""Event {l} does not exists"""    
  if l in el.ctxt.renderProcs:
    el.ctxt.render()
    
proc dispatch*(ctxt: AppContext, action: string, payload: JsonNode) =
  if ctxt.actions.haskey action:
    let action = ctxt.actions[action]
    action(payload)
  else:
    echo fmt"""Event {action} does not exists"""    
  if action in ctxt.renderProcs:
    ctxt.render()
    
proc newAppContext*(): AppContext =
  result = AppContext()
  #result.render = reRender
  result.eventHandler = eventHandler
  
  for uievk in tova.UiEventKind:
    for kev in EventKind:
      if $kev == ("on" & $uievk):
        result.eventsMap.add(uievk, kev)
        break
  
template web*(ctxt, n: untyped): untyped =
  # do not use it when element has events
  result = newUiElement(ctxt)
  result.builder =
    proc(el: UiElement): Vnode =
      buildHtml(n)
        
template web*(n: untyped): untyped =
  # do not use it when element has events
  result = newUiElement()
  result.builder =
    proc(el: UiElement): Vnode =
      buildHtml(n)
