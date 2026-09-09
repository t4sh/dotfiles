# Explicit Windows-only surfaces. Unlisted profiles, history, credentials and caches
# are not backup inputs. Slash-separated paths select individual JSON properties.
function Get-DotfilesExtraAppSpecs {
    $items=[Collections.Generic.List[hashtable]]::new()
    function Add-Extra($App,$File,$Root,$Relative,$Kind,$Paths,$Process) {
        $items.Add(@{App=$App;File=$File;Root=$Root;Relative=$Relative;Kind=$Kind;Paths=@($Paths);Process=@($Process)})
    }
    Add-Extra terminal settings.json Local 'Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json' terminal @('defaultProfile','copyFormatting','copyOnSelect','newTabMenu','profiles','schemes','themes','actions','keybindings','theme','launchMode','initialCols','initialRows','tabWidthMode','alwaysShowTabs','showTabsInTitlebar','useAcrylicInTabRow','confirmCloseAllTabs') WindowsTerminal
    Add-Extra powertoys settings.json Local 'Microsoft/PowerToys/settings.json' json @('enabled','startup','theme','system_theme','show_tray_icon','show_theme_adaptive_tray_icon','enable_quick_access','quick_access_shortcut','enable_warnings_elevated_apps','dashboard_sort_order','download_updates_automatically','include_prerelease_updates','show_new_updates_toast_notification','show_whats_new_after_updates') PowerToys
    Add-Extra deskflow settings.json Roaming 'Deskflow/Deskflow.conf' ini @('core/coreMode','core/computerName','core/port','core/processMode','client/remoteHost','client/languageSync','client/yScrollScale','client/xScrollScale','client/invertYScroll','client/invertXScroll','gui/startCoreWithGui','gui/closeToTray','security/tlsEnabled','security/checkPeerFingerprints') @('deskflow','deskflow-core')
    $modules=[ordered]@{
        AlwaysOnTop='hotkey,increase-opacity-hotkey,decrease-opacity-hotkey,frame-enabled,show-in-system-menu,frame-thickness,frame-color,frame-opacity,frame-accent-color,sound-enabled,do-not-activate-on-game-mode,excluded-apps,round-corners-enabled'
        Awake='keepDisplayOn,mode,intervalHours,intervalMinutes,customTrayTimes'
        ColorPicker='DefaultActivationShortcut,ActivationShortcut,changecursor,copiedcolorrepresentation,activationaction,primaryclickaction,middleclickaction,secondaryclickaction,colorhistorylimit,visiblecolorformats,showcolorname'
        CropAndLock='reparent-hotkey,thumbnail-hotkey,screenshot-hotkey'
        FancyZones='fancyzones_shiftDrag,fancyzones_mouseSwitch,fancyzones_mouseMiddleClickSpanningMultipleZones,fancyzones_overrideSnapHotkeys,fancyzones_moveWindowAcrossMonitors,fancyzones_moveWindowsBasedOnPosition,fancyzones_overlappingZonesAlgorithm,fancyzones_displayOrWorkAreaChange_moveWindows,fancyzones_zoneSetChange_moveWindows,fancyzones_appLastZone_moveWindows,fancyzones_openWindowOnActiveMonitor,fancyzones_restoreSize,fancyzones_quickLayoutSwitch,fancyzones_flashZonesOnQuickSwitch,use_cursorpos_editor_startupscreen,fancyzones_show_on_all_monitors,fancyzones_span_zones_across_monitors,fancyzones_makeDraggedWindowTransparent,fancyzones_allowPopupWindowSnap,fancyzones_allowChildWindowSnap,fancyzones_disableRoundCornersOnSnap,fancyzones_zoneHighlightColor,fancyzones_highlight_opacity,fancyzones_editor_hotkey,fancyzones_windowSwitching,fancyzones_nextTab_hotkey,fancyzones_prevTab_hotkey,fancyzones_monitorRotation,fancyzones_monitorRotation_hotkey,fancyzones_excluded_apps,fancyzones_zoneBorderColor,fancyzones_zoneColor,fancyzones_zoneNumberColor,fancyzones_systemTheme,fancyzones_showZoneNumber'
        FindMyMouse='DefaultActivationShortcut,activation_method,include_win_key,activation_shortcut,do_not_activate_on_game_mode,background_color,spotlight_color,spotlight_radius,animation_duration_ms,spotlight_initial_zoom,excluded_apps,shaking_minimum_distance,shaking_interval_ms,shaking_factor'
        'Keyboard Manager'='activeConfiguration,DefaultEditorShortcut,EditorShortcut,useNewEditor'
        MouseHighlighter='DefaultActivationShortcut,activation_shortcut,left_button_click_color,right_button_click_color,highlight_opacity,always_color,highlight_radius,highlight_fade_delay_ms,highlight_fade_duration_ms,auto_activate,spotlight_mode,ripple_mode,ripple_size,ripple_intensity,ripple_duration_ms,ripple_show_drag_trail,ripple_show_release_pulse'
        MouseJump='DefaultActivationShortcut,activation_shortcut,thumbnail_size,preview_type,background_color_1,background_color_2,border_thickness,border_color,border_3d_depth,border_padding,bezel_thickness,bezel_color,bezel_3d_depth,screen_margin,screen_color_1,screen_color_2'
        MousePointerCrosshairs='DefaultActivationShortcut,DefaultGlidingCursorActivationShortcut,activation_shortcut,gliding_cursor_activation_shortcut,crosshairs_color,crosshairs_opacity,crosshairs_radius,crosshairs_thickness,crosshairs_border_color,crosshairs_border_size,crosshairs_orientation,crosshairs_auto_hide,crosshairs_is_fixed_length_enabled,crosshairs_fixed_length,auto_activate,gliding_travel_speed,gliding_delay_speed'
        QuickAccent='activation_key,do_not_activate_on_game_mode,toolbar_position,input_time_ms,hold_duration_ms,selected_lang,excluded_apps,show_description,sort_by_usage_frequency,start_selection_from_the_left'
        'Shortcut Guide'='DefaultOpenShortcutGuide,open_shortcutguide,win_key_action,press_time,close_on_windows_key_release,theme,disabled_apps'
        TextExtractor='DefaultActivationShortcut,ActivationShortcut,PreferredLanguage'
        Peek='DefaultActivationShortcut,ActivationShortcut,AlwaysRunNotElevated,AlwaysOnTop,ShowTaskbarIcon,CloseAfterLosingFocus,ConfirmFileDelete,EnableSpaceToActivate,ShowFilePreviewTooltip'
        AltWindowCycle='next_window_shortcut,previous_window_shortcut'
        CursorWrap='DefaultActivationShortcut,activation_shortcut,auto_activate,disable_wrap_during_drag,wrap_mode,activation_mode,disable_cursor_wrap_on_single_monitor'
        GrabAndMove='modifierKey,shouldAbsorbAlt,showGeometry,useAltResize,doNotActivateOnGameMode,excluded_apps'
        'Measure Tool'='DefaultActivationShortcut,ActivationShortcut,ContinuousCapture,DrawFeetOnCross,PerColorChannelEdgeDetection,UnitsOfMeasure,PixelTolerance,MeasureCrossColor,DefaultMeasureStyle'
        LightSwitch='changeSystem,changeApps,lightTime,darkTime,sunrise_offset,sunset_offset,scheduleMode,toggle-theme-hotkey'
    }
    foreach($module in $modules.Keys){
        $paths=@('name','version')+@($modules[$module].Split(',') | ForEach-Object {"properties/$_"})
        Add-Extra powertoys "$module/settings.json" Local "Microsoft/PowerToys/$module/settings.json" json $paths @('PowerToys','PowerToys.*')
    }
    foreach($layout in 'custom-layouts','default-layouts','layout-hotkeys'){
        Add-Extra powertoys "FancyZones/$layout.json" Local "Microsoft/PowerToys/FancyZones/$layout.json" json @($layout) @('PowerToys','PowerToys.*')
    }
    Add-Extra powertoys 'Keyboard Manager/default.json' Local 'Microsoft/PowerToys/Keyboard Manager/default.json' json @('remapKeys/inProcess','remapShortcuts/global','remapShortcuts/appSpecific') @('PowerToys','PowerToys.*')
    Add-Extra powertoys 'Keyboard Manager/editorSettings.json' Local 'Microsoft/PowerToys/Keyboard Manager/editorSettings.json' keyboard-editor @('ShortcutSettingsDictionary','ProfileDictionary','ShortcutsByOperationType','ActiveProfile') @('PowerToys','PowerToys.*')
    Add-Extra powertoys 'Peek/preview-settings.json' Local 'Microsoft/PowerToys/Peek/preview-settings.json' json @('SourceCodeWrapText','SourceCodeTryFormat','SourceCodeFontSize','SourceCodeStickyScroll','SourceCodeMinimap') @('PowerToys','PowerToys.*')
    Add-Extra powertoys 'PowerRename/settings.json' Local 'Microsoft/PowerToys/PowerRename/power-rename-settings.json' json @('ShowIcon','ExtendedContextMenuOnly','PersistState','MRUEnabled','MaxMRUSize','UseBoostLib') @('PowerToys','PowerToys.*')
    Add-Extra sublime 'keybindings.json' Roaming 'Sublime Text/Packages/User/Default (Windows).sublime-keymap' keymap @() sublime_text
    Add-Extra zed keymap.json Roaming 'Zed/keymap.json' keymap @() zed
    $plugins=[ordered]@{
        'A File Icon'=@('size'); Markdown=@('extensions'); MultiMarkdown=@('extensions')
        MarkdownPreview=@('enable_autoreload')
        SublimeCodeIntel=@('codeintel_live_disabled_languages','codeintel_exclude_scopes_from_complete_triggers','codeintel_enabled_languages')
        SublimeLinter=@('gutter_theme','styles')
    }
    foreach($plugin in $plugins.Keys){Add-Extra sublime "$plugin.sublime-settings" Roaming "Sublime Text/Packages/User/$plugin.sublime-settings" json $plugins[$plugin] sublime_text}
    Add-Extra sublime 'my-MD-Table.sublime-snippet.json' Roaming 'Sublime Text/Packages/User/my-MD-Table.sublime-snippet' snippet @() sublime_text
    Add-Extra tower main.settings Local 'fournova/Tower/Settings/main.settings' json @(
        'GeneralSettings/FetchInterval','GeneralSettings/NumberOfCommits','GeneralSettings/ShowWarningForDiffsThreshold','GeneralSettings/DateFormatPattern','GeneralSettings/ShowDiffsForMergeCommits','GeneralSettings/DoubleClickInWorkingCopy','GeneralSettings/SpacebarInWorkingCopy','GeneralSettings/FontSizeInWorkingCopy','GeneralSettings/TruncateFilenames','GeneralSettings/SelectedTheme','GeneralSettings/ShowReflogInSidebar','GeneralSettings/ShowNumberOfStashesInSidebar','GeneralSettings/ShowStaleBadgeInSidebar','GeneralSettings/ShowFullyMergedBadgeInSidebar','GeneralSettings/StaleBranchInterval','GeneralSettings/UseCompactTopBarLayout','GeneralSettings/ShowNotifications',
        'GitSettings/SelectedDiffTool','GitSettings/SelectedMergeTool','GitSettings/GitDiffToolPerformDirectoryDiff','GitSettings/GitMergeToolKeepBackupFiles','GitSettings/UseFSCache','GitSettings/GPGEnsureKeyEmailMatchesCommitter','GitSettings/GitFlowAlwaysCreateMergeCommit','GitSettings/GitFlowUseRebaseInsteadOfMerge','GitSettings/GitFlowPreserveMergeCommits','GitSettings/UseGitCredentialManager',
        'TextSettings/ColorSyntax','TextSettings/ColorSyntaxInDiffs','TextSettings/ShowInvisibleCharacters','TextSettings/SpacesPerTab','TextSettings/SyntaxSchemeLight','TextSettings/SyntaxSchemeDark',
        'EditorSettings/EnableServiceIntegration','EditorSettings/ShowSubjectLimitCounter','EditorSettings/SubjectLineCharacterLimit','EditorSettings/LineWrappingMode','EditorSettings/EditorLineCharacterLimit','EditorSettings/ShowGuide','EditorSettings/ShowCommitTemplatesButton',
        'ShowCommitDetails','WorkingTreeSortOrder','ShowToolbarLabels','DiffContextLines','AutoExpandChangesetThreshold','FetchPruneBranches','FetchFetchAllTags','PullUseRebase','SaveStashIncludeUntrackedFiles','ApplyStashDeleteStash','ApplyStashRestoreChanges'
    ) Tower
    Add-Extra tower commit_templates.settings Local 'fournova/Tower/Settings/commit_templates.settings' json @('CommitTemplates') Tower
    $vlcPaths=@('qt-privacy-ask','metadata-network-access','save-config','fullscreen','video-on-top','video-title-show','video-title-timeout','video-title-position','snapshot-format','snapshot-prefix','snapshot-sequential','audio','volume','volume-save','audio-language','sub-language','sub-autodetect-file','sub-text-scale','freetype-font','freetype-rel-fontsize','freetype-color','freetype-outline-thickness','freetype-outline-color','qt-minimal-view','qt-system-tray','qt-notification','qt-continue','qt-recentplay','repeat','loop','random','play-and-exit','key-play-pause','key-stop','key-next','key-prev','key-fullscreen','key-vol-up','key-vol-down','key-vol-mute') | ForEach-Object {
        $section=if($_ -like 'qt-*'){'qt'}elseif($_ -like 'freetype-*'){'freetype'}elseif($_ -like 'key-*'){'hotkeys'}else{'core'}
        "$section/$_"
    }
    Add-Extra vlc vlcrc.json Roaming 'vlc/vlcrc' ini $vlcPaths vlc
    Add-Extra vlc interface.json Roaming 'vlc/vlc-qt-interface.ini' ini @('MainWindow/pl-dock-status','MainWindow/playlist-visible','MainWindow/adv-controls','MainWindow/status-bar-visible') vlc
    Add-Extra open-video-downloader preferences.json Roaming 'com.jelleglebbeek.youtube-dl-gui/preferences.store.json' json @('preferences/formats/trackType','preferences/paths/audioDirectoryTemplate','preferences/paths/audioDownloadDir','preferences/paths/videoDirectoryTemplate','preferences/paths/videoDownloadDir') @('Open Video Downloader','youtube-dl-gui')
    $caesium=[ordered]@{
        compression='keep_metadata,mode,lossless,keep_structure,jpeg_quality,jpeg_chroma_subsampling,jpeg_progressive,png_quality,png_optimization_level,webp_quality,tiff_method,tiff_deflate_level,max_output_size,max_output_size_unit'
        output='same_folder_as_input,move_original_file,output_folder,output_suffix,skip_if_bigger,keep_dates,keep_creation_date,keep_last_modified_date,keep_last_access_date,format,move_original_file_destination'
        resize='keep_aspect_ratio,do_not_enlarge,fit_to,resize,width,height,size'
    }
    foreach($group in $caesium.Keys){Add-Extra caesium "$group.json" Registry "SaeraSoft/Caesium Image Compressor/compression_options/$group" registry ($caesium[$group].Split(',')) @('Caesium Image Compressor','caesium')}
    Add-Extra 7zip options.json Registry '7-Zip/Options' registry @('CascadedMenu','ContextMenu','ElimDup','Icons') @('7zFM','7zG')
    Add-Extra 7zip fm.json Registry '7-Zip/FM' registry @('ShowDots','ShowRealFileIcons','FullRow','ShowGrid','SingleClick','AlternativeSelection','ShowSystemMenu','ShowDeletedFiles','ShowNtfsStreams','AutoRefresh','FlatView','Toolbars','ListMode','PanelMode','Lang') @('7zFM','7zG')
    return $items.ToArray()
}

function Assert-ExtraSafe($Value) {
    # Defense in depth, not a substitute for the explicit field allowlists above.
    if($Value -is [Collections.IDictionary]){
        foreach($key in $Value.Keys){
            # Boolean feature switches (e.g. PowerToys EnvironmentVariables or
            # Tower UseGitCredentialManager) contain no credential material.
            if($Value[$key] -isnot [bool] -and $key -match '(?i)password|passphrase|access.?token|refresh.?token|api.?key|authorization|credential|cookie|license|secret|sendInput|sendText|textToPaste|environment'){throw 'Excluded private/executable preference field; values were not printed.'}
            Assert-ExtraSafe $Value[$key]
        }
    } elseif($Value -is [array]){foreach($item in $Value){Assert-ExtraSafe $item}}
    elseif($Value -is [string] -and $Value -match '(?i)gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]{20,}|glpat-[A-Za-z0-9_-]+|-----BEGIN .*PRIVATE KEY-----|https?://[^/\s"]+:[^/\s"]+@|(?:password|token|secret|api[_-]?key)\s*[=:]\s*\S+'){
        throw 'Potential credential in a selected preference; values were not printed.'
    }
}
function Get-ExtraProjection($Data,[string[]]$Paths) {
    $result=[ordered]@{}
    foreach($path in $Paths){
        $segments=$path.Split('/');$value=$Data;$found=$true
        foreach($segment in $segments){if($value -isnot [Collections.IDictionary] -or -not $value.Contains($segment)){$found=$false;break};$value=$value[$segment]}
        if(-not $found){continue}
        $cursor=$result
        for($i=0;$i -lt $segments.Count-1;$i++){if(-not $cursor.Contains($segments[$i])){$cursor[$segments[$i]]=[ordered]@{}};$cursor=$cursor[$segments[$i]]}
        $cursor[$segments[-1]]=$value
    }
    return $result
}
function Merge-ExtraPreferences($Existing,$Patch) {
    if($Existing -is [Collections.IDictionary] -and $Patch -is [Collections.IDictionary]){
        foreach($key in $Patch.Keys){$Existing[$key]=Merge-ExtraPreferences $Existing[$key] $Patch[$key]};return $Existing
    }
    return ,$Patch
}
function Convert-ExtraPaths($Value,[string]$UserRoot,[switch]$Restore) {
    if($Value -is [Collections.IDictionary]){ $copy=[ordered]@{};foreach($key in $Value.Keys){$copy[$key]=Convert-ExtraPaths $Value[$key] $UserRoot -Restore:$Restore};return $copy }
    if($Value -is [array]){return ,@($Value | ForEach-Object {Convert-ExtraPaths $_ $UserRoot -Restore:$Restore})}
    if($Value -is [string]){
        if($Restore){return $Value.Replace('__USERPROFILE__',$UserRoot)}
        return $Value.Replace($UserRoot,'__USERPROFILE__').Replace($UserRoot.Replace('\','/'),'__USERPROFILE__')
    }
    return $Value
}
function Convert-ExtraJson($Value) { return (ConvertTo-Json -InputObject $Value -Depth 80 -Compress) }
function Assert-ExtraRoot($Data,$Spec) {
    if($Spec.Kind -notin @('keymap','snippet') -and $Data -isnot [Collections.IDictionary]){
        throw 'Settings must be a JSON object; values not printed.'
    }
}
function Assert-ExtraTerminalCommands($Value) {
    # Commands can occur in profiles, defaults, actions and nested action groups.
    if($Value -is [Collections.IDictionary]){
        foreach($key in $Value.Keys){
            if($key -iin @('action','command') -and $Value[$key] -is [string] -and $Value[$key] -ieq 'sendInput'){
                throw 'Terminal sendInput action needs explicit review; input values were not printed.'
            }
            if($key -ieq 'commandline' -and ($Value[$key] -isnot [string] -or $Value[$key] -notmatch '(?i)^"?(?:(?:%SystemRoot%|C:\\Windows)\\System32\\(?:WindowsPowerShell\\v1\.0\\)?|C:\\Program Files\\PowerShell\\7\\)?(?:cmd|powershell|pwsh|wsl)\.exe"?$')){
                throw 'Terminal has a custom shell command that needs explicit review before backup.'
            }
            Assert-ExtraTerminalCommands $Value[$key]
        }
    }elseif($Value -is [array]){foreach($item in $Value){Assert-ExtraTerminalCommands $item}}
}
function Select-ExtraData($Data,$Spec) {
    Assert-ExtraRoot $Data $Spec
    if($Spec.Kind -in @('keymap','snippet')){$selected=$Data}
    else{$selected=Get-ExtraProjection $Data $Spec.Paths}
    if($Spec.App -eq 'powertoys' -and $Spec.File -eq 'Keyboard Manager/default.json'){
        foreach($remap in @($selected.remapKeys.inProcess)+@($selected.remapShortcuts.global)+@($selected.remapShortcuts.appSpecific)){
            if($null -ne $remap -and $remap.Contains('operationType') -and $remap.operationType -ne 0){throw 'Keyboard Manager program/URI action requires separate review; values not printed.'}
        }
    }
    if($Spec.Kind -eq 'keyboard-editor'){
        if($selected.ProfileDictionary.Count){throw 'Named Keyboard Manager profiles need explicit schema review.'}
        $entries=[ordered]@{}
        foreach($id in $selected.ShortcutSettingsDictionary.Keys){
            $entry=$selected.ShortcutSettingsDictionary[$id];$shortcut=$entry.Shortcut
            if($shortcut.OperationType -ne 0 -or $shortcut.TargetText -or $shortcut.ProgramPath -or $shortcut.ProgramArgs -or $shortcut.StartInDirectory -or $shortcut.UriToOpen){throw 'Keyboard Manager text/program/URI action requires separate review; values not printed.'}
            $entries[$id]=Get-ExtraProjection $entry @('Id','Shortcut/OriginalKeys','Shortcut/TargetKeys','Shortcut/TargetApp','Shortcut/OperationType','Profiles','IsActive')
        }
        $selected.ShortcutSettingsDictionary=$entries
    }
    if($Spec.Kind -eq 'keymap' -and $selected -isnot [array]){throw 'Keymap must be a JSON array.'}
    if($Spec.Kind -eq 'snippet'){
        if($selected -isnot [string]){throw 'Snippet must be text.'}
        if($selected -match '(?i)<!DOCTYPE|<!ENTITY'){throw 'Unsupported snippet XML.'}
        $xml=[xml]$selected
        if($xml.DocumentElement.Name -ne 'snippet'){throw 'Unsupported snippet XML.'}
    }
    if($Spec.Kind -eq 'terminal'){Assert-ExtraTerminalCommands $selected}
    Assert-ExtraSafe $selected
    return ,$selected
}
