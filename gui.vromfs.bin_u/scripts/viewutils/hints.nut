//-file:plus-string
from "%scripts/dagui_library.nut" import *
let { handyman } = require("%sqStdLibs/helpers/handyman.nut")

let { split_by_chars } = require("string")
enum HINT_PIECE_TYPE {
  TEXT,
  TAG,
  LINK
}

let function getTextSlice(textsArray) {
  return { text = textsArray.map(
    @(text, idx) { textValue = textsArray?[idx + 1] != null ? $"{text} " : text }) }
}


::g_hints <- {
  hintTags = ["{{", "}}"]
  timerMark = ::g_hint_tag.TIMER.typeName
  colorTags = ["<color=", "</color>"]
  linkTags = ["<Link=", "</Link>"]
}

/*
  params:
  * id          //null
  * style       //""
  * time        //0 - only to show time in text
  * timeoffset  //0 - only to show time in text
*/
::g_hints.buildHintMarkup <- function buildHintMarkup(text, params = {}) {
  return handyman.renderCached("%gui/hint.tpl", this.getHintSlices(text, params))
}

::g_hints.getHintSlices <- function getHintSlices(text, params = {}) {
  let rows = split_by_chars(text, "\n")
  let isWrapInRowAllowed = params?.isWrapInRowAllowed ?? false
  let view = {
    id = getTblValue("id", params)
    style = getTblValue("style", params, "")
    isOrderPopup = getTblValue("isOrderPopup", params, false)
    isWrapInRowAllowed = isWrapInRowAllowed
    flowAlign = getTblValue("flowAlign", params, "center")
    animation = getTblValue("animation", params)
    isVerticalAlignText = params?.isVerticalAlignText ?? false
    rows = []
  }

  let colors = [] //array of opened color tags, contains color itself

  foreach (row in rows) {
    let slices = []
    let needProtectSplitLinks = (isWrapInRowAllowed && row.indexof(this.linkTags[0]) != null)
    let rawRowPieces = this.splitRowToPieces(row, needProtectSplitLinks)
    let needSplitByWords = isWrapInRowAllowed && rawRowPieces.len() > 1

    foreach (rawRowPiece in rawRowPieces) {
      if (rawRowPiece.type == HINT_PIECE_TYPE.TEXT || rawRowPiece.type == HINT_PIECE_TYPE.LINK ) {
        local piece = rawRowPiece.piece
        local carriage = 0
        local unclosedTags = 0
        local textsArray = []
        local lastIdxOfSlicedPiece = 0

        while (true) {
          let openingColorTagStartIndex = piece.indexof(this.colorTags[0], carriage)
          let closingColorTagStartIndex = piece.indexof(this.colorTags[1], carriage)

          //move carriage
          if (openingColorTagStartIndex != null && closingColorTagStartIndex != null)
            carriage = min(
              openingColorTagStartIndex + this.colorTags[0].len(),
              closingColorTagStartIndex + this.colorTags[1].len()
            )
          else if (closingColorTagStartIndex != null)
            carriage = closingColorTagStartIndex + this.colorTags[1].len()
          else if (openingColorTagStartIndex != null)
            carriage = openingColorTagStartIndex + this.colorTags[0].len()
          else
            break

          //closing tag found, pop color from stack and continue
          if (openingColorTagStartIndex == null ||
            (openingColorTagStartIndex ?? -1) > (closingColorTagStartIndex ?? -1)) {
            if (unclosedTags > 0)
              unclosedTags--
            else {
              let lenBefore = piece.len()
              piece = "<color=" + colors.top() + ">" + piece
              carriage += piece.len() - lenBefore
            }

            colors.pop()
            if (needSplitByWords && colors.len() == 0 && rawRowPiece.type == HINT_PIECE_TYPE.TEXT) {
              textsArray.append(piece.slice(lastIdxOfSlicedPiece, carriage))
              lastIdxOfSlicedPiece = carriage
            }
          }
          //opening tag found, add color to stack, increment unclosedTags counter
          else if (openingColorTagStartIndex != null && openingColorTagStartIndex < (closingColorTagStartIndex ?? -1)) {
            let colorEnd = piece.indexof(">", openingColorTagStartIndex)
            let colorStart = openingColorTagStartIndex + this.colorTags[0].len()
            colors.append(piece.slice(colorStart, colorEnd))
            unclosedTags++
          }
        }

        //close all unclosed tags
        for (local i = 0; i < unclosedTags; ++i)
          piece += this.colorTags[1]

        if (colors.len() > 0)
          piece = colorize(colors.top(), piece)

        if (piece.len()) {
          if (rawRowPiece.type == HINT_PIECE_TYPE.LINK || colors.len() > 0 || !needSplitByWords)
            textsArray = [piece]
          else {
            let lastPiece = piece.slice(lastIdxOfSlicedPiece, piece.len())
            if (lastPiece != "")
              textsArray.extend(lastPiece.split(" "))
          }

          slices.append(getTextSlice(textsArray))
        }
      }
      else if (rawRowPiece.type == HINT_PIECE_TYPE.TAG) {
        let tagType = ::g_hint_tag.getHintTagType(rawRowPiece.piece)
        slices.extend(tagType.getViewSlices(rawRowPiece.piece, params))
      }
    }

    view.rows.append({ slices = slices })
  }

  if (colors.len())
    log("unclosed <color> tag! in text: " + text)

  return view
}


let function findLinks(oldSlices) {
  let oldlen = oldSlices.len()
  let slices = []
  for ( local i = 0; i < oldlen; i++) {
    local oldSlice = oldSlices[i]
    if (oldSlice.type == HINT_PIECE_TYPE.TAG) {
      slices.append(oldSlice)
      continue
    }
    let linkIndex = oldSlice.piece.indexof(this.linkTags[0])
    if (linkIndex == null) {
      slices.append(oldSlice)
      continue
    }
    let linkEndIndex = oldSlice.piece.indexof(this.linkTags[1], linkIndex)
    if (linkEndIndex == null) {
      slices.append(oldSlice)
      continue
    }
    slices.append({
      type = HINT_PIECE_TYPE.TEXT,
      piece = oldSlice.piece.slice(0, linkIndex)
    })
    slices.append({
      type = HINT_PIECE_TYPE.LINK
      piece = oldSlice.piece.slice(linkIndex, linkEndIndex + this.linkTags[1].len())
    })
    slices.append({
      type = HINT_PIECE_TYPE.TEXT,
      piece = oldSlice.piece.slice(linkEndIndex + this.linkTags[1].len(), oldSlice.piece.len())
    })
  }
  return slices
}


/**
 * Split row to atomic parts to work with
 * @return array of strings with type specifieres (text or tag)
 */
::g_hints.splitRowToPieces <- function splitRowToPieces(row, needProtectSplitLinks = false) {
  let slices = []
  while (row.len() > 0) {
    let tagStartIndex = row.indexof(this.hintTags[0])

    //no tags on current row
    //put entire row in one piece and exit
    if (tagStartIndex == null) {
      slices.append({
        type = HINT_PIECE_TYPE.TEXT,
        piece = row
      })
      break
    }

    let tagEndIndex = row.indexof(this.hintTags[1], tagStartIndex)
    //there is unclosed tag
    //flush current row content to one piece and exit
    if (tagEndIndex == null) {
      slices.append({
        type = HINT_PIECE_TYPE.TEXT,
        piece = row
      })
      break
    }

    //slice piece before tag
    slices.append({
      type = HINT_PIECE_TYPE.TEXT,
      piece = row.slice(0, tagStartIndex)
    })

    //slice piece that contains tag
    slices.append({
      type = HINT_PIECE_TYPE.TAG
      piece = row.slice(tagStartIndex + this.hintTags[0].len(), tagEndIndex)
    })

    row = row.slice(tagEndIndex + this.hintTags[1].len())
  }

  return (needProtectSplitLinks && slices.len() > 1) ? findLinks(slices) : slices
}


::cross_call_api.getHintConfig <- @(text) ::g_hints.getHintSlices(text, { needConfig = true })
