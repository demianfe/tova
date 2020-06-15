
import json, tables, jsffi, strutils, times, asyncjs

include karax / prelude
import karax / prelude
import karax / [vdom, karaxdsl, kdom]

import listeners

import tova, build, actions

var console {. importc, nodecl .}: JsObject

var
  initialized = false
  prevHashPart: cstring
  ctxt: AppContext
  app: UiApp

proc setHashRoute(rd: RouterData) =
  echo rd.hashPart
  if prevHashPart != $rd.hashPart:
    ctxt.route = $rd.hashPart
    ctxt.state["route"] = %($rd.hashPart)
    prevHashPart = $rd.hashPart
  elif $prevHashPart != ctxt.route:
    window.location.href = cstring(ctxt.route)
    prevHashPart = window.location.hash  

proc showError(): VNode =
  result = buildHtml(tdiv(class="container")):
    tdiv(class="alert alert-danger",role="alert"):
      h3:
        text "Error:"
      p:
        text ctxt.state["error"].getStr
      a(href="#/home"):
        text "Go back home."
  ctxt.state.delete("error")
  reRender()

proc initNavigation() =
  try:
    ctxt.route = $window.location.hash
    ctxt.state["route"] = %($window.location.hash)
    prevHashPart = window.location.hash
  except:
    let e = getCurrentException()
    echo e.msg

proc handleCreateDomException(): Vnode =
  let e = getCurrentException()
  var msg: string
  if not e.isNil:
    msg = e.getStackTrace()
    echo("===================================== ERROR ===================================")
    echo getCurrentExceptionMsg()
    echo(msg)
    echo("================================================================================")
  else:
    msg = "Builder Error: Something went wrong."
    ctxt.state["error"] = %msg
    result = showError()

# uses app instead of ctxt
proc createAppDOM(rd: RouterData): VNode =
  if ctxt.location[0] != "":
    window = window.open(ctxt.location[0], ctxt.location[1])
    ctxt.location = ("", "")
    
  try:
    setHashRoute(rd)
    if ctxt.state.hasKey("error"):
      result = showError()      
    elif app.state == "ready":
      result = updateUI(app)
    elif app.state == "loading":
      result = buildHtml(tdiv()):
        p:
          text "Loading ..."
      result = initApp(app)
      app.state = "ready"
    else:
      echo "App invalid state."      
  except:
    result = handleCreateDomException()
    echo "exception"
    
template App*(appId, name: string, Layout: untyped): untyped =
  ctxt = newAppContext()
  ctxt.state = %*{}
  ctxt.route = "#/login"
  
  proc init(): Future[void] {.async.} =
    app = UiApp()
    await initActions ctxt
    app.ctxt = ctxt
    app.id = appId
    app.title = name
    app.state = "loading"
    app.ctxt.actions = tova_actions
    app.ctxt.renderProcs = render_tova_procs
    app.layout = Layout
    ctxt = app.ctxt
    loadDefaultActions(app)
    initNavigation()
    `kxi` = setRenderer(createAppDOM)
    app.ctxt.kxi = `kxi`
    app.ctxt.window = window
    app.ctxt.document = document
                              
  discard init()
