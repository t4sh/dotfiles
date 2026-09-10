# Cursor extension maintenance

Reviewed 2026-09-09 against the user's 26-extension list, the installed VS Code
package manifests, Cursor's bundled extensions, and Cursor's own catalog/CLI.

## Selected installation

`esbenp.prettier-vscode` replaces the separate CSS/SCSS/Less beautifier.
Prettier does not replace ESLint, SVGO, Autoprefixer, or Nunjucks formatting.
Projects own formatting configuration; select the formatter in Cursor when needed.
The public Cursor snapshot retains its minimal font and built-in theme settings.

On macOS, `make cursor-extensions` installs Prettier. Both `make brew-base`
and `make brew-apps` invoke it after package installation. Cursor's installer
preserves existing extensions. Brewfile continues to own VS Code intent.

On Windows, `dot extensions -Editor cursor -Apply` uses
`config/windows-extensions.tsv`. This review narrows the requested 26 entries;
the other previously declared Windows extensions remain part of that workflow.
Excluded extensions already present are retained, not automatically uninstalled.

## Case-by-case decisions

Google Cloud Data Agent Kit (`googlecloudtools.datacloud`) is intentionally
removed from the shared Brewfile. Its startup installer recreated 30 unwanted
skills under the globally linked `~/.agents/skills` directory on Windows.
Google Cloud Code (`googlecloudtools.cloudcode`) is also removed because it
requires Data Agent Kit and would reinstall it. Gemini Code Assist remains
independently selected. On existing VS Code and Cursor installations, uninstall
Cloud Code first, then Data Agent Kit; removing Brewfile entries alone does not
uninstall existing extensions. Restart open editors before removing generated
Data Cloud skills and their `.datacloud_skills_manifest`.

| Requested extension | Cursor decision |
| --- | --- |
| `1000ch.svgo` | Defer. Use project-pinned SVGO in the asset pipeline. |
| `ahmadalli.vscode-nginx-conf` | Defer. Choose one NGINX provider when needed, not two overlapping providers. |
| `andrejunges.handlebars` | Bundled Handlebars syntax covers basic editing. Additional snippets are optional. |
| `bbugh.change-color-format` | Built-in CSS color picker handles common formats. Defer advanced conversions. |
| `burkeholland.simple-react-snippets` | Defer. Add project/user snippets when repetitive React patterns justify them. |
| `dhedgecock.ember-syntax` | Defer until an Ember/Glimmer project needs extended syntax. |
| `fabiospampinato.vscode-open-multiple-files` | Use Explorer multi-select or CLI paths. Defer bulk glob opening. |
| `figma.figma-vscode-extension` | Defer. Use Figma app/browser; configure Figma MCP for design-to-code work when needed. |
| `github.codespaces` | Defer until Codespaces is actually used; use browser or local clones meanwhile. |
| `jacobcofman.changelog` | Defer package.json changelog hovers; read package release notes directly. |
| `jasonn-porch.gitlab-mr` | Defer. Use GitLab web or glab; assess the official GitLab extension for an in-editor MR requirement. |
| `jasonnutter.search-node-modules` | Use built-in search with ignore/exclude filtering disabled for that query. Defer dedicated navigation. |
| `kostasx.live-html-previewer-v2` | Use the project dev server and browser; defer standalone live preview. |
| `matteopieroni.refresh-npm-packages` | Use the repository's explicit package-manager/lockfile workflow. No automatic install prompt helper. |
| `michelemelluso.code-beautifier` | Replace with `esbenp.prettier-vscode`, selected for project formatting. |
| `mike-co.import-sorter` | Use built-in Organize Imports. Custom ordering belongs in project lint rules; not all custom sort behavior is equivalent. |
| `mrmlnc.vscode-autoprefixer` | Defer. Use project PostCSS/Autoprefixer plus Browserslist in the build. |
| `ms-vscode.remote-repositories` | Defer virtual remote workspaces; local clones cover the baseline workflow. |
| `ms-vscode.vscode-chat-customizations-evaluations` | Defer this specialized VS Code prompt-evaluation workflow. |
| `pushqrdx.inline-html` | Defer until HTML/CSS tagged templates need language support. Plain HTML support does not cover this feature. |
| `riazxrazor.html-to-jsx` | Defer. Review occasional conversions manually or with Cursor; this is not an automatic built-in converter. |
| `ronnidc.nunjucks` | Defer: Cursor installer reported not found. Review a source-published grammar when a Nunjucks project needs it. |
| `sidthesloth.html5-boilerplate` | Use built-in Emmet `!` expansion. |
| `t-sauer.autolinting-for-javascript` | Use explicitly selected project ESLint/Biome tooling. No automatic linter-selector extension. |
| `tal7aouy.indent-colorizer` | Use built-in indentation guides. Rainbow indentation is optional and deferred. |
| `william-voyek.vscode-nginx` | Defer: Cursor installer reported not found. It was the narrow syntax-only candidate. |

## Evidence and limits

- Prettier 12.4.0 installed successfully through Cursor's native CLI on this Mac.
- Nunjucks and NGINX candidate installs returned `not found`; public catalog
  searches returned no candidates for those terms. Availability can change.
- No VS Code extension directories were copied or repackaged into Cursor.
- Cursor's installed application contains Handlebars, HTML/CSS, Emmet, Git,
  and TypeScript support. These cover the basic built-in decisions above;
  optional extension-specific features are explicitly deferred.
- Installation inventory and package assets are separate from real editor
  activation, rendering, or formatting behavior. Native Windows installation
  and activation were not exercised on this Mac.

Primary references:

- [Prettier extension: supported languages, project resolution and configuration](https://github.com/prettier/prettier-vscode)
- [Emmet is built in](https://code.visualstudio.com/docs/languages/emmet)
- [CSS editing and color picker](https://code.visualstudio.com/docs/languages/css)
- [Organize Imports](https://code.visualstudio.com/updates/v1_68#_group-aware-organize-imports)
- [Nunjucks syntax/snippets](https://marketplace.visualstudio.com/items?itemName=ronnidc.nunjucks)
- [NGINX syntax-only candidate](https://marketplace.visualstudio.com/items?itemName=william-voyek.vscode-nginx)
- [NGINX language helper](https://marketplace.visualstudio.com/items?itemName=ahmadalli.vscode-nginx-conf)
- [Figma MCP](https://developers.figma.com/docs/figma-mcp-server/)
- [Official GitLab editor integration](https://docs.gitlab.com/editor_extensions/visual_studio_code/)

## Integration and validation

The Windows implementation is integrated with the Mac maintenance changes on
private `main`. Native Windows validation of
`2962123 chore(windows): apply reviewed Cursor extension scope` passed 161 checks
and actual isolated Apply/Check for 109 VS Code and 81 Cursor requirements.
Existing extras and Cursor's bundled Jupyter keymap were preserved.
The iCloud shortcut remains private; public projection and publication are
separate steps. GUI activation and fresh-machine acceptance remain unrun.
