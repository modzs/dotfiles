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
    -- mkdp defines its three commands buffer-locally, from a filetype-gated autocmd, so
    -- ft alone is what makes them exist. a lazy cmd stub cannot help: measured, in a
    -- markdown buffer ft+cmd and ft-only are identical, while in a non-markdown buffer
    -- the stub turns a clean E492 into a silent no-op
    ft = 'markdown',
    -- builds the preview server from the vendored app/ with the node home.nix
    -- already installs, rather than downloading a prebuilt binary
    build = 'cd app && npx --yes yarn@1.22.22 install',
  },
}
