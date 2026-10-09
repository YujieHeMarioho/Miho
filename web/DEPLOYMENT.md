# GitHub Pages release

Source is maintained in `feat/miho-browser`, under `web/`. The `gh-pages` branch contains only the built static site and `.nojekyll`; it has no user audio, native models, runtime libraries or logs.

For the first release, a repository administrator must configure Settings → Pages → Build and deployment → Deploy from a branch → `gh-pages` → `/ (root)` → Save. A repository connection able to push content does not necessarily have permission or an API to change Pages settings. Confirm the URL and successful build shown by GitHub before calling the site live.

Subsequent releases are deliberate/manual: run `npm ci`, `npm test`, `npm run build` inside `web/`, test `dist/` under `/Miho/`, then publish the resulting `dist/` files to the existing `gh-pages` branch without force-pushing. No automatic source-branch deployment workflow is configured.

The site is static and needs no server-side service, credentials, paid API or uploaded audio. The page explicitly identifies its current amplitude/frequency analysis as algorithms, not AI inference.
