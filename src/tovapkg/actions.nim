# default actions for embeded ui components

import tables, json, strutils
import tova

proc loadDefaultActions*(app: var UiApp) =
  app.ctxt.actions.add "close_message",
     proc(payload: JsonNode) =
       var id = -1
       if payload.haskey("objid"):
         id = parseInt(payload["objid"].getStr)
       elif payload.haskey("id"):
         id = parseInt(payload["id"].getStr)
       if id != -1:
         app.ctxt.messages.delete(id)
       app.ctxt.render()
