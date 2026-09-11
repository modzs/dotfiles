return {
  {
    'MeanderingProgrammer/render-markdown.nvim',
    ft = 'markdown',
    -- nvim ships the markdown and markdown_inline parsers this reads a buffer
    -- with, so no nvim-treesitter here; see AGENTS.md
    opts = {},
  },
  {
    'iamcco/markdown-preview.nvim',
    -- all three names, so lazy stubs each one and any works typed first; no ft, auto-start is off
    cmd = { 'MarkdownPreview', 'MarkdownPreviewStop', 'MarkdownPreviewToggle' },
    -- builds the preview server from the vendored app/ with the node home.nix
    -- already installs, rather than downloading a prebuilt binary
    build = 'cd app && npx --yes yarn@1.22.22 install',
  },
}
