# Installed directly by restore-apps; no make link prerequisite.
import sublime
import sublime_plugin

DEFAULT_SYNTAX = "Packages/Markdown/MultiMarkdown.sublime-syntax"

class DefaultSyntaxCommand(sublime_plugin.EventListener):
    def on_new(self, view):
        if sublime.syntax_from_path(DEFAULT_SYNTAX) is None:
            sublime.status_message(
                "Default syntax unavailable: install the Markdown package, then restart Sublime Text."
            )
            return
        view.assign_syntax(DEFAULT_SYNTAX)
