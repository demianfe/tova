
import macros
import json, tables, sequtils, strutils
export tables

proc createEventsTable(): NimNode =
  result = nnkIdentDefs.newTree(
    nnkPostfix.newTree(
      newIdentNode("*"),
      newIdentNode("tova_actions")
    ),
    newEmptyNode(),
    nnkCall.newTree(
      nnkBracketExpr.newTree(
        newIdentNode("initTable"),
        newIdentNode("cstring"),
        nnkProcTy.newTree(
          nnkFormalParams.newTree(
            newEmptyNode(),
            nnkIdentDefs.newTree(
              newIdentNode("payload"),
              newIdentNode("JsonNode"),
              newEmptyNode()
            )
          ),
          nnkPragma.newTree(
            newIdentNode("closure")
          )
        )
      )
    )
  )

# proc createAsyncEventsTable(): NimNode =
#   result = nnkIdentDefs.newTree(
#     nnkPostfix.newTree(
#       newIdentNode("*"),
#       newIdentNode("async_tova_actions")
#     ),
#     newEmptyNode(),
#     nnkCall.newTree(
#       nnkBracketExpr.newTree(
#         newIdentNode("initTable"),
#         newIdentNode("cstring"),
#         nnkProcTy.newTree(
#           nnkFormalParams.newTree(
#             nnkBracketExpr.newTree(
#               newIdentNode("Future"),
#               nnkDotExpr.newTree(
#                 newIdentNode("system"),
#                 newIdentNode("void")
#               )
#             ),
#             nnkIdentDefs.newTree(
#               newIdentNode("payload"),
#               newIdentNode("JsonNode"),
#               newEmptyNode()
#             )
#           ),
#           nnkPragma.newTree(
#             newIdentNode("closure")
#           )
#         )
#       )
#     )
#   )

proc createRenderSeq(): NimNode =
  result =
    nnkIdentDefs.newTree(
      nnkPostfix.newTree(
        newIdentNode("*"),
        newIdentNode("render_tova_procs")
      ),
      nnkBracketExpr.newTree(
        newIdentNode("seq"),
        newIdentNode("string")
      ),
      nnkPrefix.newTree(
        newIdentNode("@"),
        nnkBracket.newTree(
        )
      )
    )
  
proc addEventListener(n: NimNode): NimNode =  
  result = nnkCall.newTree(
    nnkDotExpr.newTree(
      newIdentNode("tova_actions"),
      newIdentNode("add")
    ),
    nnkCallStrLit.newTree(
      newIdentNode("cstring"),      
      newLit($n[0].ident)
    ),
    newIdentNode($n[0].ident)
  )

# proc addAsyncEventListener(n: NimNode): NimNode =  
#   result = nnkCall.newTree(
#     nnkDotExpr.newTree(
#       newIdentNode("async_tova_actions"),
#       newIdentNode("add")
#     ),
#     nnkCallStrLit.newTree(
#       newIdentNode("cstring"),      
#       newLit($n[0].ident)
#     ),
#     newIdentNode($n[0].ident)
#   )

proc addRenderProc(n: NimNode): NimNode =
  result = nnkCall.newTree(
    nnkDotExpr.newTree(
      newIdentNode("render_tova_procs"),
      newIdentNode("add")
    ),
    newLit($n[0].ident)
  )
  
# get all anotations
# proc isAsync(n: NimNode): bool =
#   for c in n.children:
#     if c.kind == nnkPragma:
#       if c[0].kind == nnkIdent and c[0].strVal == "async":
#         result = true
#         break

proc getPragmas(n: NimNode): seq[string] =
  for c in n.children:
    if c.kind == nnkPragma:
      for p in c.children:
        if p.kind == nnkIdent:
          echo p.strVal
          result.add p.strVal
      
template render* {.pragma.}

macro EventHandlers*(n: untyped): untyped =
  # actions table
  result = nnkStmtList.newTree(
    nnkVarSection.newTree(
      createEventsTable(),
     # createAsyncEventsTable(),
      createRenderSeq()
    )
  )
  var evNames:seq[string] = @[]
  if n.kind == nnkStmtList:
    for x in n.children:
      result.add x
      if x.kind == nnkProcDef:
        let evName = x[0].strVal
        if evNames.contains evName:
          let msg = " Trtying to add the same event twice: " & evName
          raise newException(Exception, msg)
        
        evnames.add evName
        let pragmas = getPragmas(x)
        # if "async" in pragmas:
        #   echo "Adding async " & evName
        #   result.add addAsyncEventListener(x)  
        # else:
        #   echo "Adding " & evName
        #   result.add addEventListener(x)
        result.add addEventListener(x)
        if "render" in pragmas:
          echo "Adding Render proc: " & evName
          result.add addRenderProc(x)
        
