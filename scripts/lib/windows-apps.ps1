# Only explicitly managed preference namespaces are captured; auth/MCP/env/history never are.
function Select-DotfilesPreferences {
    param([Collections.IDictionary]$Settings, [string]$Editor)
    $allowed = switch ($Editor) {
        'zed' { '^(theme|icon_theme|ui_font_family|ui_font_size|buffer_font_family|buffer_font_fallbacks|buffer_font_size|buffer_line_height|base_keymap|multi_cursor_modifier|vim_mode|relative_line_numbers|tab_size|soft_wrap|format_on_save|autosave|telemetry|inlay_hints|indent_guides|scrollbar|gutter|project_panel|outline_panel|terminal|languages|auto_install_extensions|auto_indent_on_paste|colorize_brackets|current_line_highlight|ensure_final_newline_on_save|line_ending|linked_edits|remove_trailing_whitespace_on_save|show_edit_predictions|show_whitespaces|minimap|sticky_scroll|diagnostics|git|file_types)$' }
        'sublime' { '^(theme|color_scheme|font_face|font_size|font_options|tab_size|translate_tabs_to_spaces|detect_indentation|auto_indent|smart_indent|word_wrap|rulers|line_padding_top|line_padding_bottom|margin|draw_white_space|highlight_line|highlight_modified_tabs|show_encoding|show_line_endings|ensure_newline_at_eof_on_save|trim_trailing_white_space_on_save|default_line_ending|ignored_packages|installed_packages|index_files|save_on_focus_lost|caret_style|wide_caret|bold_folder_labels|folder_exclude_patterns|file_exclude_patterns|always_show_minimap_viewport|minimap|remember_open_files|hot_exit)$' }
        default { '^(editor\.|files\.|workbench\.|window\.|breadcrumbs\.|explorer\.|search\.|diffEditor\.|scm\.|git\.|terminal\.integrated\.(font|cursor|defaultProfile|profiles|scrollback)|\[|prettier\.|eslint\.|python\.(defaultInterpreterPath|analysis)|monokai-pro\.|activitusbar\.|cSpell\.|html\.|javascript\.|typescript\.|markdown\.|markdownlint\.|peacock\.|scss\.|colorize\.|yaml\.)' }
    }
    $safe = [ordered]@{}
    foreach ($key in $Settings.Keys) {
        # Interpreter caches belong to the local runtime manager, not a snapshot.
        if ($key -eq 'python.defaultInterpreterPath') { continue }
        if (($key -notmatch $allowed -and -not ($Editor -eq 'sublime' -and $key -match '^(gruvbox_|caret_extra_|line_numbers$|auto_complete$|draw_minimap_border$|fade_fold_buttons$|indent_guide_options$|match_brackets_angle$|open_files_in_new_window$|overlay_scroll_bars$|spell_check$)')) -or $key -match '(?i)token|secret|password|api.?key|headers|mcp|environment|\.env($|\.)') { continue }
        $serialized = ConvertTo-Json -InputObject $Settings[$key] -Depth 50 -Compress
        if ($serialized -match '(?i)"(?:token|secret|password|api.?key|headers|env|environment)"\s*:|gh[pousr]_[A-Za-z0-9]{20,}|sk-[A-Za-z0-9_-]{20,}|-----BEGIN .*PRIVATE KEY-----|https?://[^/\s"]+:[^/\s"]+@') { continue }
        $safe[$key] = $Settings[$key]
    }
    return $safe
}
function Convert-DotfilesPreferencePaths($Value, [switch]$Restore) {
    if ($Value -is [Collections.IDictionary]) {
        $result=[ordered]@{}
        foreach($key in $Value.Keys){$result[$key]=Convert-DotfilesPreferencePaths $Value[$key] -Restore:$Restore}
        return $result
    }
    if ($Value -is [string]) {
        if($Restore){return $Value.Replace('__USERPROFILE__',$HOME)}
        return $Value.Replace($HOME,'__USERPROFILE__').Replace(($HOME -replace '\\','/'),'__USERPROFILE__')
    }
    if ($Value -is [array]) { return ,@($Value | ForEach-Object {Convert-DotfilesPreferencePaths $_ -Restore:$Restore}) }
    return $Value
}
function Get-DotfilesAppMappings([string]$RoamingRoot) {
    @(
        @{Editor='vscode';File='settings.json';Live=(Join-Path $RoamingRoot 'Code\User\settings.json');Process='Code'},
        @{Editor='cursor';File='settings.json';Live=(Join-Path $RoamingRoot 'Cursor\User\settings.json');Process='Cursor'},
        @{Editor='zed';File='settings.json';Live=(Join-Path $RoamingRoot 'Zed\settings.json');Process='zed'},
        @{Editor='sublime';File='Preferences.sublime-settings';Live=(Join-Path $RoamingRoot 'Sublime Text\Packages\User\Preferences.sublime-settings');Process='sublime_text'},
        @{Editor='sublime';File='Package Control.sublime-settings';Live=(Join-Path $RoamingRoot 'Sublime Text\Packages\User\Package Control.sublime-settings');Process='sublime_text'}
    )
}
