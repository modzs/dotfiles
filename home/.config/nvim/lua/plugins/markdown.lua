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
    -- mkdp defines its three commands buffer-locally from an autocmd, so ft is what makes
    -- them exist in a buffer already open; the cmd entries are lazy's stubs for a cold session
    ft = 'markdown',
    cmd = { 'MarkdownPreview', 'MarkdownPreviewStop', 'MarkdownPreviewToggle' },
    -- builds the preview server from the vendored app/ with the node home.nix
    -- already installs, rather than downloading a prebuilt binary
    build = 'cd app && npx --yes yarn@1.22.22 install',
  },
}
