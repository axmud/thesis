# usage

```cmd
set PROJECT=thesis
git clone https://github.com/axmud/thesis.git %PROJECT%
winget install typst -v 0.14.2
cd %PROJECT%
typst compile main.typ --font-path fonts --ignore-system-fonts
```
