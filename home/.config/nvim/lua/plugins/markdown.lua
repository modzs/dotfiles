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
    cmd = { 'MarkdownPreview', 'MarkdownPreviewStop', 'MarkdownPreviewToggle' },
    ft = 'markdown',
    -- builds the preview server from the vendored app/ with the node home.nix
    -- already installs, rather than downloading a prebuilt binary
    build = 'cd app && npx --yes yarn install',
  },
}
