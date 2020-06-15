
import tables, json, strutils

include karax / prelude
import karax / [kbase, vdom, karaxdsl]

import tova, utils

const containersKind = [
  UiElementKind.kUiElement,
  UiElementKind.kHeader,
  UiElementKind.kNavBar,
  UiElementKind.kNavSection]

proc callBuilder(elem: UiElement): VNode =
  var el = elem
  if not el.builder.isNil:
    result = el.builder(elem)
  elif el.kind == UiElementKind.kUiElement and el.attributes.len > 0:
    result = buildHtml(tdiv())
    result.addAttributes el

  elif el.kind == UiElementKind.kUiElement:
    for kid in el.children:
      result = callBuilder(kid)

  if not result.isNil:
    for elkid in el.children:
      let kid = callBuilder(elkid)
      if not kid.isNil:
        result.add kid

proc payload(el: UiElement): JsonNode =
  result = %*{
    "id": el.id,
    "field": el.field,
    "label": el.label,
    "value": el.value,
    "kind": el.kind,
    "type": el.objectType
  }
      
proc buildElement(uiel: UiElement): VNode =
  var el: UiElement = uiel

  try:
    if el.kind in containersKind:
      if not el.builder.isNil:
        result = el.builder(el)
      else:
        result = buildHtml(tdiv())
      result.addAttributes el
      
      for c in el.children:
        let vkid = buildElement(c)
        if not vkid.isNil:
          result.add vkid
    else:
      if not el.builder.isNil:
        result = callBuilder(el)
        result.addAttributes el      
  except:
    var msg = ""
    let e = getCurrentException()
    if not e.isNil:
      msg = e.getStackTrace()
    else:
      msg = getCurrentExceptionMsg()
      
    result = buildHtml(tdiv):
      echo "Error - Element build fail: " & $el.kind
      echo el.builder.isNil
      echo msg      
      h4: text "Error - Element build fail: " & $el.kind
      h6: text getCurrentExceptionMsg()
      p: text msg
    
proc updateUI*(app: var UiApp): VNode =
  var
    state = app.ctxt.state
    action: string

  result = newVNode VnodeKind.tdiv
  
  if app.ctxt.route != "":
    let
      sr = app.ctxt.route.split("?")
    if sr.len > 1:
      app.ctxt.route = sr[0]
      let qs = sr[1].split("&")
      for q in qs:
        let kv = q.split("=")
        if kv.len > 1:
          app.ctxt.queryString.add kv[0], kv[1]
        else:
          app.ctxt.queryString.add kv[0], kv[0]
    
    action = app.ctxt.route.replace("#/", "")
    if app.ctxt.actions.haskey action:
      # call action
      var payload = %*{"action": action}
      app.ctxt.actions[action](payload)

  let h = buildElement(app.layout(app.ctxt))
  if not h.isNil:
    result.add h
  
proc initApp*(app: var UiApp): VNode =
  result = updateUI(app)

