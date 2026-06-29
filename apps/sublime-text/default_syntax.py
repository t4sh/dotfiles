# Add this script in your SublimeText Packages/User directory
import sublime, sublime_plugin

class DefaultSyntaxCommand(sublime_plugin.EventListener):
   def on_new(self, view):
    view.set_syntax_file('Packages/Markdown/MultiMarkdown.tmLanguage')
