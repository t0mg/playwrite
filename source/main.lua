import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"

local pd<const> = playdate
local gfx<const> = pd.graphics

local keyboardInputAngleOffset<const> = 100

local fontHeight
local linesPerScreen
local cursorOffsetFromBottom<const> = 1
local marginH<const> = 4
local screenWidth, screenHeight = pd.display.getSize()
local textLineMaxWidth = screenWidth - 2*marginH
local cursorDark = true
local scrollTimer = nil
local text = {{}}
local drawBuffer = {}
local drawBufferDirty = true
local mainFontFamily = nil
local sysFont<const> = pd.graphics.getSystemFont(pd.graphics.kFileWrite)

local cursorPosition = {
    paragraphIndex = 1,
    lineIndex = 1,
    lineIndexBeforeInput = 1,
    indexInLine = 1
}

function shiftCursorHoriz(right)
    cursorDark = true
    if right then
        -- move to the right
        if cursorPosition.indexInLine <= string.len(text[cursorPosition.paragraphIndex][cursorPosition.lineIndex]) then
            cursorPosition.indexInLine += 1 -- and we' re done here.
        else
            -- end of line reached
            if cursorPosition.lineIndex < #text[cursorPosition.paragraphIndex] then
                -- jump to next line
                cursorPosition.indexInLine = 1
                cursorPosition.lineIndex += 1
                animateLineScroll()
            else
                -- end of paragraph reached
                if cursorPosition.paragraphIndex < #text then
                    -- jump to next paragraph
                    cursorPosition.indexInLine = 1
                    cursorPosition.lineIndex = 1
                    cursorPosition.paragraphIndex += 1
                    animateLineScroll()
                end
            end
        end
    else
        -- move to the left
        if cursorPosition.indexInLine > 1 then
            cursorPosition.indexInLine -= 1 -- and we're done here.
        else
            -- start of line reached
            if cursorPosition.lineIndex > 1 then
                -- jump to prev line
                cursorPosition.lineIndex -= 1
                cursorPosition.indexInLine = string.len(text[cursorPosition.paragraphIndex][cursorPosition.lineIndex]) + 1
                animateLineScroll(true)
            else
                -- start of paragraph reached
                if cursorPosition.paragraphIndex > 1 then
                    -- jump to end of previous paragraph
                    cursorPosition.paragraphIndex -= 1
                    cursorPosition.lineIndex = #text[cursorPosition.paragraphIndex]
                    cursorPosition.indexInLine = string.len(text[cursorPosition.paragraphIndex][cursorPosition.lineIndex]) + 1
                    animateLineScroll(true)
                end
            end
        end
    end
    drawText()
end

function shiftCursorVert(bottom)
    cursorDark = true
    function clampNewIndexInLine()
        cursorPosition.indexInLine = math.min(string.len(text[cursorPosition.paragraphIndex][cursorPosition.lineIndex]) + 1, cursorPosition.indexInLine)
        cursorPosition.indexInLine = math.max(cursorPosition.indexInLine, 1)
    end

    if bottom then
        -- move one line down
        if cursorPosition.lineIndex < #text[cursorPosition.paragraphIndex] then
            cursorPosition.lineIndex += 1
            clampNewIndexInLine()
            animateLineScroll()
        else
            if cursorPosition.paragraphIndex < #text then
                -- move to next paragraph
                cursorPosition.paragraphIndex += 1
                cursorPosition.lineIndex = 1
                clampNewIndexInLine()
                animateLineScroll()
            end
        end
    else
        -- move one line up
        if cursorPosition.lineIndex > 1 then
            cursorPosition.lineIndex -= 1
            clampNewIndexInLine()
            animateLineScroll(true)
        else
            if cursorPosition.paragraphIndex > 1 then
                -- move to previous paragraph
                cursorPosition.paragraphIndex -= 1
                cursorPosition.lineIndex = #text[cursorPosition.paragraphIndex]
                clampNewIndexInLine()
                animateLineScroll(true)
            end
        end
    end
    drawText()
end

function animateLineScroll(up)
    -- since we're moving to a new line we need to update the text buffer
    drawBufferDirty = true

    local mult = 1
    if (up == true) then mult = -1 end
    scrollTimer = pd.timer.new(300, fontHeight * mult, 0, pd.easingFunctions.outCubic)
    scrollTimer.updateCallback = drawText
end

function drawCursor()
    gfx.setLineWidth(2)
    local cursorLine = linesPerScreen - cursorOffsetFromBottom
    if cursorDark then gfx.setColor(gfx.kColorBlack) else gfx.setColor(gfx.kColorWhite) end
    local font<const> = gfx.getFont()
    local textLine = text[cursorPosition.paragraphIndex][cursorPosition.lineIndex]
    local posx = 0
    if textLine and cursorPosition.indexInLine > 1 then
        textLine = string.sub(textLine, 1, cursorPosition.indexInLine - 1)
        posx = font:getTextWidth(textLine)
    end
    posx += 5
    local scrollOffset = 0
    if (scrollTimer) then scrollOffset = scrollTimer.value end
    gfx.drawLine(posx, fontHeight * (cursorLine - 1) + scrollOffset, posx, fontHeight * cursorLine + scrollOffset)
end

function updateDrawBuffer()
    -- the -1 below is to draw one text line above the screen in case of scroll animation
    local firstLineToDraw = cursorPosition.lineIndex - linesPerScreen + cursorOffsetFromBottom

    drawBuffer = {}
    -- look if we need to fill the render buffer with lines from prevous paragraph
    if firstLineToDraw <= 0 then
        local paragraphSeek = cursorPosition.paragraphIndex - 1
        local linesToBuffer = math.abs(firstLineToDraw) + 1
        -- take the last lines from previous paragraph
        while paragraphSeek >= 1 and linesToBuffer >= 1 do
            local lineSeek = #text[paragraphSeek]
            -- copy lines to the buffer
            while lineSeek >= 1 and linesToBuffer >= 1 do
                table.insert(drawBuffer, 1, text[paragraphSeek][lineSeek])
                lineSeek -= 1
                linesToBuffer -= 1
            end
            paragraphSeek -= 1
        end
        -- if couldn't fill the back buffer entirely, add padding
        while linesToBuffer > 0 do
            table.insert(drawBuffer, 1, "")
            linesToBuffer -= 1
        end
    end

    -- we have now backfilled negative index lines to draw, update firstLineToDraw accordingly
    firstLineToDraw = math.max(1, firstLineToDraw)

    -- concat buffer with current paragraph
    for index, line in ipairs(text[cursorPosition.paragraphIndex]) do
        if (#drawBuffer > linesPerScreen + 1) then break end
        if (index >= firstLineToDraw) then
            table.insert(drawBuffer, line)
        end
    end

    -- do we need to buffer lines from subsequent paragraphs?
    local lookAheadParagraph = cursorPosition.paragraphIndex + 1
    while #drawBuffer <= linesPerScreen + 1 and lookAheadParagraph <= #text do
        for _, line in ipairs(text[lookAheadParagraph]) do
            if (#drawBuffer > linesPerScreen + 1) then break end
            table.insert(drawBuffer, line)
        end
        -- paragraph copied entirely, look at the next one
        lookAheadParagraph += 1
    end

    -- printTable(drawBuffer)
    drawBufferDirty = false
end

function drawText()
    gfx.clear()
    gfx.setColor(gfx.kColorBlack)

    if drawBufferDirty then
        updateDrawBuffer()
    end

    for i = 1, #drawBuffer do
        local textLine = drawBuffer[i]
        if textLine ~= nil and textLine ~= "" then
            local scrollOffset = 0
            if (scrollTimer ~= nil) then scrollOffset = scrollTimer.value end
            local yPos = (i - 2) * fontHeight + scrollOffset
            gfx.drawText(textLine, marginH, yPos)
        end
    end
    drawCursor()

    local len = string.len(table.concat(text[cursorPosition.paragraphIndex],""))
    sysFont:drawTextAligned(len, 398, 220, kTextAlignment.right)
end

function enableKeyboardInput(enable)
    if (enable) then
        print("KeyboardInputEnable")
    else
        print("KeyboardInputDisable")
    end
end

function readyForNextInput()
    print("ReadyForNextInput")
end

function reflowCurrentParagraphFromLine(line)
    local font<const> = gfx.getFont()
    local i = line

    while i <= #text[cursorPosition.paragraphIndex] do
        local textLine = text[cursorPosition.paragraphIndex][i]
        if font:getTextWidth(textLine) > textLineMaxWidth then
            local maxLen = 60
            local breakIndex
            local cutLine = textLine
            while font:getTextWidth(cutLine) > textLineMaxWidth do
                maxLen -= 1
                local sub = string.sub(textLine, 1, maxLen)
                sub = sub:reverse()
                local whitespaceIndex = string.find(sub, " ")
                if whitespaceIndex == nil then
                    -- no whitespace found, gotta cut the line anyway...
                    whitespaceIndex = 1
                end
                breakIndex = sub:len() - whitespaceIndex + 1
                cutLine = string.sub(textLine, 1, breakIndex)
            end
            text[cursorPosition.paragraphIndex][i] = cutLine
            local remainder = string.sub(textLine, breakIndex + 1)
            if i == #text[cursorPosition.paragraphIndex] then
                table.insert(text[cursorPosition.paragraphIndex], i + 1, "")
            end
            text[cursorPosition.paragraphIndex][i + 1] = remainder..text[cursorPosition.paragraphIndex][i + 1]
            if i == cursorPosition.lineIndex and cursorPosition.indexInLine > cutLine:len() then
                cursorPosition.lineIndex += 1
                cursorPosition.indexInLine -= cutLine:len()
            end
        end
        i += 1
    end
    if (cursorPosition.lineIndexBeforeInput ~= cursorPosition.lineIndex) then
        animateLineScroll(cursorPosition.lineIndexBeforeInput > cursorPosition.lineIndex)
    end
end

function insertChar(input)
    cursorPosition.lineIndexBeforeInput = cursorPosition.lineIndex
    local currentLine = text[cursorPosition.paragraphIndex][cursorPosition.lineIndex]
    if currentLine == nil then currentLine = "" end
    local firstHalf = string.sub(currentLine, 1, cursorPosition.indexInLine - 1)
    local secondHalf = string.sub(currentLine, cursorPosition.indexInLine)
    currentLine = firstHalf..input..secondHalf
    if cursorPosition.lineIndex > 1 then
        local prevLineLength = text[cursorPosition.paragraphIndex][cursorPosition.lineIndex - 1]:len()
        text[cursorPosition.paragraphIndex][cursorPosition.lineIndex - 1] = text[cursorPosition.paragraphIndex][cursorPosition.lineIndex - 1]..currentLine
        table.remove(text[cursorPosition.paragraphIndex], cursorPosition.lineIndex)
        cursorPosition.lineIndex -= 1
        cursorPosition.indexInLine += prevLineLength
    else
        text[cursorPosition.paragraphIndex][cursorPosition.lineIndex] = currentLine
    end
    reflowCurrentParagraphFromLine(math.max(1, cursorPosition.lineIndex - 1))
    drawBufferDirty = true
    shiftCursorHoriz(true)
end

function removeChar()
    -- early exit if we're already at the top of the document
    if cursorPosition.paragraphIndex == 1 and cursorPosition.lineIndex == 1 and cursorPosition.indexInLine == 1 then return end

    drawBufferDirty = true

    -- if we're at the beginning of a paragraph...
    if cursorPosition.lineIndex == 1 and cursorPosition.indexInLine == 1 then
        -- set future cursor line and index in line as the end of the previous paragraph
        cursorPosition.lineIndex = #text[cursorPosition.paragraphIndex - 1]
        cursorPosition.indexInLine = string.len(text[cursorPosition.paragraphIndex - 1][cursorPosition.lineIndex]) + 1

        -- if #text[cursorPosition.paragraphIndex] > 1 then
            --- merge the current paragraph with the previous one
            local mergeResult = text[cursorPosition.paragraphIndex - 1]
                -- append the current line to the previous paragraph's last line (to trigger reflow later)
            mergeResult[#mergeResult] = mergeResult[#mergeResult] .. table.remove(text[cursorPosition.paragraphIndex], 1)
            while #text[cursorPosition.paragraphIndex] > 1 do
                table.insert(mergeResult, table.remove(text[cursorPosition.paragraphIndex], 1))
            end
            text[cursorPosition.paragraphIndex - 1] = mergeResult
        -- end
        -- remove the now empty paragraph
        table.remove(text, cursorPosition.paragraphIndex)

        cursorPosition.paragraphIndex -= 1
        reflowCurrentParagraphFromLine(cursorPosition.lineIndex)
        -- shiftCursorHoriz(true) -- this is a hack to fix a bug!
        drawText()
    else
        -- otherwise remove one character from the current cursor position in the line and reflow the text
        cursorPosition.lineIndexBeforeInput = cursorPosition.lineIndex
        if cursorPosition.indexInLine == 1 then shiftCursorHoriz(false) end
        local currentLine = text[cursorPosition.paragraphIndex][cursorPosition.lineIndex]
        if text[cursorPosition.paragraphIndex][cursorPosition.lineIndex]:len() == 1 then
            text[cursorPosition.paragraphIndex][cursorPosition.lineIndex] = ""
        else
            local firstHalf = ""
            if cursorPosition.indexInLine > 1 then
                firstHalf = string.sub(currentLine, 1, cursorPosition.indexInLine - 2)
            end
            local secondHalf = string.sub(currentLine, cursorPosition.indexInLine)
            -- merge current and next line
            local nextLine = table.remove(text[cursorPosition.paragraphIndex], cursorPosition.lineIndex + 1) or ""
            text[cursorPosition.paragraphIndex][cursorPosition.lineIndex] = firstHalf..secondHalf..nextLine
        end
        reflowCurrentParagraphFromLine(cursorPosition.lineIndex)
        shiftCursorHoriz(false)
    end
end

function saveJson ()
    pd.datastore.write(text, "doc")
end

function loadJson()
    text = pd.datastore.read("doc")
    local lastParagraph = #text
    local lastLine = #(text[lastParagraph])
    local lastChar = string.len(text[lastParagraph][lastLine])
    cursorPosition = {
        paragraphIndex = lastParagraph,
        lineIndex = lastLine,
        lineIndexBeforeInput = lastLine,
        indexInLine = lastChar
    }
    drawBufferDirty = true
    shiftCursorHoriz(true)
    drawText()
end

function saveTxt()
    local flatParagraphs = {}
    for _, paragraph in ipairs(text) do
        table.insert(flatParagraphs, table.concat(paragraph,""))
    end
    local flattenedText = table.concat(flatParagraphs, "\n")
    local txtfile = pd.file.open("export.txt", pd.file.kFileWrite)
    if txtfile ~= nil then
        txtfile:write(flattenedText)
        txtfile:close()
    end
end

function setupGame()
	local fontPaths = {
		[gfx.font.kVariantNormal] = "fonts/noto-serif-regular"
	}
	mainFontFamily = gfx.font.newFamily(fontPaths)
	gfx.setFontFamily(mainFontFamily)
	fontHeight = mainFontFamily[gfx.font.kVariantNormal]:getHeight()
    linesPerScreen = math.ceil(screenHeight / fontHeight)
    
	gfx.setColor(gfx.kColorBlack)

    local font<const> = gfx.getFont()
    local greeting<const> = "Playwrite"
    local w<const> = font:getTextWidth(greeting)
    local h<const> = font:getHeight()
    local x<const> = (screenWidth - w) / 2
    local y<const> = (screenHeight - h) / 2
    gfx.drawText(greeting, x, y)

    pd.setCrankSoundsDisabled(true)
    enableKeyboardInput(true)

    local menu = pd.getSystemMenu()
    menu:addMenuItem('save', {}, saveJson)
    menu:addMenuItem('load', {}, loadJson)
    menu:addMenuItem('export', {}, saveTxt)

    local function blinkCallback()
        cursorDark = not cursorDark
    end
    pd.timer.keyRepeatTimerWithDelay(500, 500, blinkCallback)
end
setupGame()

-- local index = 0
-- local dummy = {'p','l','a','y',',',' ','w','r','i','t','e','!','b'}
function insertLineBreak()
    -- A quick hack to produce a few keystrokes without the keyboard dock
    -- so I can test the code using the simulator.
    -- index += 1
    -- if index > #dummy then index = 1 end
    -- if dummy[index] ~= "b" then
    --     insertChar(dummy[index])
    --     return
    -- end

    cursorPosition.lineIndexBeforeInput = cursorPosition.lineIndex
    local currentParagraph = text[cursorPosition.paragraphIndex]
    local currentLine = currentParagraph[cursorPosition.lineIndex]
    if currentLine == nil then currentLine = "" end
    local firstHalf = string.sub(currentLine, 1, cursorPosition.indexInLine - 1)
    local secondHalf = string.sub(currentLine, cursorPosition.indexInLine)
    -- cut the line in the current paragraph
    currentParagraph[cursorPosition.lineIndex] = firstHalf
    -- prepare a new paragraph to be inserted
    local newParagraph = {}
    if #currentParagraph == cursorPosition.lineIndex then
        -- it only contains the second half of the cut line
        table.insert(newParagraph, secondHalf)
    else
        -- there are more lines, prepend the second half to the next line to trigger reflow
        table.insert(newParagraph, secondHalf .. table.remove(currentParagraph, cursorPosition.lineIndex + 1))
        -- then move any subsequent lines to the new paragraph
        while #currentParagraph > cursorPosition.lineIndex do
            table.insert(newParagraph, table.remove(currentParagraph, cursorPosition.lineIndex + 1))
        end
    end
    cursorPosition.paragraphIndex += 1
    table.insert(text, cursorPosition.paragraphIndex, newParagraph)
    cursorPosition.lineIndex = 1
    cursorPosition.indexInLine = 1
    reflowCurrentParagraphFromLine(1)
    animateLineScroll()
end

local crankin = 0
function pd.cranked(change, _)
    print("crank change ".. change)
    if (math.abs(change) < keyboardInputAngleOffset) then
        crankin += change
        if(math.abs(crankin) > 25) then
            shiftCursorVert(crankin > 0)
            crankin = 0
        end
        return
    end

    -- values above 180 transmitted via serial are automatically converted to a negative angle (360 - value)
    -- so we make the value positive again.
    if change < 0 then
        change += 360
    end

    local value = math.min(math.max(32, math.floor(change - keyboardInputAngleOffset + 0.5)), 255)
    print('value '..value)

    local char = string.char(value)
    print(char)
    insertChar(char)
    readyForNextInput()
end

function pd.update()
    gfx.sprite.update()
    pd.timer.updateTimers()
    drawCursor()
end

local keyTimerUp = nil
local keyTimerDown = nil
local keyTimerLeft = nil
local keyTimerRight = nil
local keyTimerA = nil
local keyTimerB = nil

function pd.upButtonDown()
    local function timerCallback()
        shiftCursorVert(false)
    end
    keyTimerUp = pd.timer.keyRepeatTimer(timerCallback)
end

function pd.downButtonDown()
    local function timerCallback()
       shiftCursorVert(true)
    end
    keyTimerDown = pd.timer.keyRepeatTimer(timerCallback)
end

function pd.leftButtonDown()
    local function timerCallback()
        shiftCursorHoriz(false)
    end
    keyTimerLeft = pd.timer.keyRepeatTimer(timerCallback)
end

function pd.rightButtonDown()
    local function timerCallback()
        shiftCursorHoriz(true)
    end
    keyTimerRight = pd.timer.keyRepeatTimer(timerCallback)
end

function pd.AButtonDown()
    local function timerCallback()
        insertLineBreak()
    end
    keyTimerA = pd.timer.keyRepeatTimer(timerCallback)
end

function pd.BButtonDown()
    local function timerCallback()
        removeChar()
    end
    keyTimerB = pd.timer.keyRepeatTimer(timerCallback)
end

function pd.upButtonUp()
    keyTimerUp:remove()
end

function pd.downButtonUp()
    keyTimerDown:remove()
end

function pd.leftButtonUp()
    keyTimerLeft:remove()
end

function pd.rightButtonUp()
    keyTimerRight:remove()
end

function pd.AButtonUp()
    keyTimerA:remove()
end

function pd.BButtonUp()
    keyTimerB:remove()
end

function pd.gameWillTerminate()
    enableKeyboardInput(false)
end

function pd.deviceWillLock()
    enableKeyboardInput(false)
end

function pd.deviceDidUnlock()
    enableKeyboardInput(true)
end

function pd.gameWillPause()
    enableKeyboardInput(false)
end

function pd.gameWillResume()
    enableKeyboardInput(true)
end