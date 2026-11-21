-- Dumps the Accessibility tree of every UI the AirDrop discoverability workflow clicks through,
-- so that the ordinal paths in src/info.plist can be updated for a new Mac OS version.
--
-- It changes no settings: it only opens the AirDrop/Bluetooth Menu Bar modules, Control Centre,
-- a Finder AirDrop window and its discoverability pop-up, and closes them again with ESC.
--
-- Its output does contain personal data though: the user's name (AirDrop shows it), identifiers of paired
-- Bluetooth devices (their addresses), mounted volumes and servers, running processes and so on. So write it
-- to an ignored location such as _stuff/ and never commit it.
--
-- Usage, from the repository root (the terminal application needs Accessibility permission), sections are
-- "agents", "menubar" and "finder", with "agents" and "finder" by default:
--
--   mkdir -p ./_stuff
--   osascript ./debugging/dump-airdrop-ui.applescript [agents] [menubar] [finder] > ./_stuff/ui-dump.txt 2>&1 && say 'UI dumping is done'
--
-- "agents" dumps everything under the system processes that host Menu Bar icons, whatever its class,
-- which is how the icons are found with Mac OS 27.2.1, where they are not menu bar items of ControlCenter
-- anymore; "menubar" is how they were found up to Mac OS 26
--
-- The Control Centre panels only show what the current state allows (for example, the AirDrop panel lists
-- the discoverability levels only while AirDrop is on), so dump in the state that shows the controls.
--
-- After you are done with debugging, it is probably best if you revoke the Accessibility permission
-- from that terminal application, for example if it was iTerm2:
--
--   tccutil reset Accessibility com.googlecode.iterm2
--   tccutil reset AppleEvents com.googlecode.iterm2
--

property out : ""
property menuBarItemsFound : {} -- {process name, menu bar item, its description and title}

on run argv
    if (count argv) is 0 then
        set sections to {"agents", "finder"}
    else
        set sections to argv
    end if

    set out to "Mac OS " & (system version of (system info)) & ", " & ((current date) as text) & linefeed & linefeed

    if sections contains "menubar" then
        try
            dumpMenuBars()
        on error errMsg number errNum
            addLine("!! Menu Bar section failed: " & errMsg & " (" & errNum & ")")
        end try
        clickMenuBarModules()
    end if

    if sections contains "agents" then
        try
            dumpMenuBarAgents()
        on error errMsg number errNum
            addLine("!! Agents section failed: " & errMsg & " (" & errNum & ")")
        end try
        clickMenuBarModules()
    end if

    if sections contains "finder" then
        try
            dumpFinderAirDrop()
        on error errMsg number errNum
            addLine("!! Finder section failed: " & errMsg & " (" & errNum & ")")
        end try
    end if

    return out
end run

-- every menu bar of every process, except application menus (menu bars starting with the Apple menu);
-- up to Mac OS 26 the icons the workflow clicks were in menu bar 1 of process ControlCenter
on dumpMenuBars()
    addLine("=== Menu bars of every process (application menus skipped) ===")
    set menuBarItemsFound to {}
    tell application "System Events" to set procs to processes
    repeat with procRef in procs
        set proc to contents of procRef
        set processName to "?"
        try
            tell application "System Events"
                set processName to name of proc
                with timeout of 5 seconds
                    set barCount to count menu bars of proc
                end timeout
            end tell
            repeat with barIndex from 1 to barCount
                tell application "System Events"
                    with timeout of 5 seconds
                        set barItems to menu bar items of menu bar barIndex of proc
                    end timeout
                end tell
                set firstTitle to ""
                if (count barItems) > 0 then set firstTitle to attrText(item 1 of barItems, "AXTitle")
                if firstTitle is not "Apple" then
                    addLine("--- process \"" & processName & "\", menu bar " & barIndex & ": " & (count barItems) & " item(s)")
                    repeat with barItemRef in barItems
                        set barItem to contents of barItemRef
                        describeElement(barItem)
                        set end of menuBarItemsFound to {processName, barItem, attrText(barItem, "AXDescription") & " " & attrText(barItem, "AXTitle")}
                    end repeat
                end if
            end repeat
        on error errMsg number errNum
            -- most processes have no menu bars or no UI at all, so only timeouts are worth reporting
            if errNum is -1712 then addLine("!! process \"" & processName & "\" timed out")
        end try
    end repeat
    addLine("")
end dumpMenuBars

-- everything under the processes that hosted (up to Mac OS 26) or might now host Apple's Menu Bar icons
on dumpMenuBarAgents()
    tell application "System Events" to set processNames to name of every process
    addLine("=== All processes ===")
    addLine(joinList(processNames, ", "))
    addLine("")
    set menuBarItemsFound to {}
    repeat with processRef in {"MenuBarAgent", "ControlCenter", "SystemUIServer"}
        set processName to contents of processRef
        try
            dumpProcessDeep(processName)
        on error errMsg number errNum
            addLine("!! process " & processName & ": " & errMsg & " (" & errNum & ")")
        end try
        addLine("")
    end repeat
end dumpMenuBarAgents

on dumpProcessDeep(processName)
    tell application "System Events"
        set proc to process processName
        set procAttrs to name of attributes of proc
        set barCount to count menu bars of proc
        set winCount to count windows of proc
    end tell
    addLine("=== Process " & processName & ": " & barCount & " menu bar(s), " & winCount & " window(s) ===")
    addLine("attributes: " & joinList(procAttrs, ", "))

    -- the Accessibility API's own attribute for the menu bar holding menu extras, not necessarily one of "menu bars"
    try
        tell application "System Events" to set extrasBar to value of attribute "AXExtrasMenuBar" of proc
        addLine("--- AXExtrasMenuBar")
        collectTree(processName, extrasBar)
    on error errMsg number errNum
        addLine("--- no AXExtrasMenuBar: " & errMsg & " (" & errNum & ")")
    end try

    repeat with barIndex from 1 to barCount
        tell application "System Events"
            set bar to menu bar barIndex of proc
            set barAttrs to name of attributes of bar
            set childCount to count UI elements of bar
        end tell
        addLine("--- menu bar " & barIndex & ": " & childCount & " child element(s), attributes: " & joinList(barAttrs, ", "))
        collectTree(processName, bar)
    end repeat

    repeat with winIndex from 1 to winCount
        tell application "System Events" to set win to window winIndex of proc
        addLine("--- window " & winIndex)
        collectTree(processName, win)
    end repeat
end dumpProcessDeep

-- dumps the tree and remembers its elements as candidates for clickMenuBarModules()
on collectTree(processName, rootElem)
    set elems to dumpTree(rootElem)
    repeat with e in elems
        set uiElem to contents of e
        set end of menuBarItemsFound to {processName, uiElem, attrText(uiElem, "AXDescription") & " " & attrText(uiElem, "AXTitle") & " " & attrText(uiElem, "AXIdentifier")}
    end repeat
end collectTree

on clickMenuBarModules()
    -- "Control Cent" matches both spellings of the description (up to Mac OS 26),
    -- "controlcenter" the com.apple.menuextra.controlcenter identifier (Mac OS 27.2.1)
    repeat with itemRef in {"AirDrop", "Bluetooth", "Control Cent", "controlcenter"}
        set itemName to contents of itemRef
        try
            dumpMenuBarModule(itemName)
        on error errMsg number errNum
            addLine("!! " & itemName & " module section failed: " & errMsg & " (" & errNum & ")")
            pressEscape()
        end try
    end repeat
end clickMenuBarModules

-- clicks the first menu bar item found above that mentions itemName, and dumps the windows it opens
on dumpMenuBarModule(itemName)
    set found to false
    repeat with foundRef in menuBarItemsFound
        if (item 3 of foundRef) contains itemName then
            set found to true
            set processName to item 1 of foundRef
            set barItem to item 2 of foundRef
            exit repeat
        end if
    end repeat
    if not found then
        addLine("=== No Menu Bar item mentioning \"" & itemName & "\" ===")
        addLine("")
        return
    end if

    addLine("=== Clicked " & refText(barItem) & " (mentions \"" & itemName & "\") ===")
    tell application "System Events" to click barItem
    delay 1

    dumpWindows(processName)
    if processName is not "ControlCenter" then
        try
            dumpWindows("ControlCenter")
        on error errMsg number errNum
            addLine("!! no windows of process ControlCenter: " & errMsg & " (" & errNum & ")")
        end try
    end if

    pressEscape()
end dumpMenuBarModule

on dumpWindows(processName)
    tell application "System Events" to tell process processName
        set wins to windows
    end tell
    addLine("--- " & (count wins) & " window(s) of process " & processName)
    repeat with w in wins
        dumpTree(contents of w)
    end repeat
    addLine("")
end dumpWindows

-- the Finder fallback: a new Finder window switched to AirDrop, then the "Allow me to be discovered by" pop-up
on dumpFinderAirDrop()
    tell application "Finder"
        make new Finder window
        activate
    end tell
    delay 1
    tell application "System Events" to tell process "Finder"
        keystroke "R" using {command down, shift down}
    end tell
    delay 2

    -- which part of the path used by workflow version 1.0.0 still resolves
    tell application "System Events" to tell process "Finder"
        set windowName to name of window 1
        set e1 to exists splitter group 1 of window 1
        set e2 to exists splitter group 1 of splitter group 1 of window 1
        set e3 to exists group 1 of splitter group 1 of splitter group 1 of window 1
        set e4 to exists button 2 of group 1 of splitter group 1 of splitter group 1 of window 1
        set e5 to exists button 1 of group 1 of splitter group 1 of splitter group 1 of window 1
        set finderWindow to window 1
    end tell
    addLine("=== Finder window 1 (\"" & windowName & "\") after Shift-Cmd-R ===")
    addLine("1.0.0 path check: splitter group 1 = " & e1 & ", splitter group 1 of splitter group 1 = " & e2 & ", group 1 of that = " & e3 & ", button 2 of that group = " & e4 & ", button 1 of that group = " & e5)
    set elems to dumpTree(finderWindow)
    addLine("")

    -- heuristic for the discoverability pop-up: a button mentioning "discover" or one of the levels
    set found to false
    repeat with e in elems
        set uiElem to contents of e
        if attrText(uiElem, "AXRole") is in {"AXButton", "AXPopUpButton", "AXMenuButton"} then
            set elemText to attrText(uiElem, "AXTitle") & " " & attrText(uiElem, "AXDescription") & " " & attrText(uiElem, "AXValue")
            repeat with kw in {"discover", "No One", "Contacts Only", "Everyone"}
                if elemText contains (contents of kw) then
                    set found to true
                    exit repeat
                end if
            end repeat
        end if
        if found then
            set candidate to uiElem
            exit repeat
        end if
    end repeat

    if found then
        addLine("=== Clicked " & refText(candidate) & " (heuristic guess at the discoverability pop-up) ===")
        tell application "System Events" to click candidate
        delay 1
        tell application "System Events" to tell process "Finder"
            set winNames to name of windows
            set finderWindow to window 1
        end tell
        addLine("--- Finder windows now: " & joinList(winNames, ", "))
        dumpTree(finderWindow)
        addLine("")
        pressEscape()
    else
        addLine("=== No discoverability pop-up candidate found, nothing clicked ===")
        addLine("")
    end if

    tell application "Finder" to close first window
end dumpFinderAirDrop

-- describes the element and everything below it, returns the list of descendants
on dumpTree(rootElem)
    describeElement(rootElem)
    tell application "System Events" to set elems to entire contents of rootElem
    repeat with e in elems
        describeElement(contents of e)
    end repeat
    return elems
end dumpTree

on describeElement(uiElem)
    set s to "  " & refText(uiElem)
    repeat with attrPair in {{"role", "AXRole"}, {"subrole", "AXSubrole"}, {"title", "AXTitle"}, {"desc", "AXDescription"}, {"value", "AXValue"}, {"id", "AXIdentifier"}, {"pos", "AXPosition"}, {"size", "AXSize"}}
        set attrValue to attrText(uiElem, item 2 of attrPair)
        if attrValue is not "" then set s to s & " | " & (item 1 of attrPair) & "=" & attrValue
    end repeat
    addLine(s)
end describeElement

-- empty when the element has no such attribute or it has no value
on attrText(uiElem, attrName)
    try
        tell application "System Events" to set attrValue to value of attribute attrName of uiElem
    on error
        return ""
    end try
    if attrValue is missing value then return ""
    try
        if class of attrValue is list then return joinList(attrValue, ",")
        return attrValue as text
    on error
        return "(" & ((class of attrValue) as text) & ")"
    end try
end attrText

-- a UI element reference can't be coerced to text, but the coercion error message spells out its full path
on refText(uiElem)
    try
        set p to uiElem as text
    on error errMsg
        set startPos to offset of "make " in errMsg
        set endPos to offset of " into type" in errMsg
        if startPos > 0 and endPos > startPos then
            set p to text (startPos + 5) thru (endPos - 1) of errMsg
        else
            set p to errMsg
        end if
    end try
    set suffix to " of application \"System Events\""
    if p ends with suffix then set p to text 1 thru ((length of p) - (length of suffix)) of p
    return p
end refText

on joinList(theList, delimiter)
    set savedDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to delimiter
    set joined to theList as text
    set AppleScript's text item delimiters to savedDelimiters
    return joined
end joinList

on addLine(s)
    set out to out & s & linefeed
end addLine

on pressEscape()
    tell application "System Events" to key code 53 -- ESC
    delay 0.5
end pressEscape
