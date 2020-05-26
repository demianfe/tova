# default actions for embeded ui components

import tables, json, strutils
import tova

proc loadDefaultActions*(app: var UiApp) =
  app.ctxt.actions.add "close_message",
     proc(payload: JsonNode) =
       if payload.haskey("objid"):
         let id = parseInt(payload["objid"].getStr)
         app.ctxt.messages.delete(id)
       app.ctxt.render()

  # app.ctxt.actions.add "toggle_burger",
  #   proc(payload: JsonNode) =
  #     echo payload
  #     if payload.haskey("objid"):
  #       echo payload
  #       # let id = parseInt(payload["objid"].getStr)
  #       # app.ctxt.messages.delete(id)x
  #       app.ctxt.render()
