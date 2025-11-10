-- Enable TypeSpec
vim.lsp.enable("tsp_server")

return {
  "vinnymeller/swagger-preview.nvim",
  cmd = { "SwaggerPreview", "SwaggerPreviewStop", "SwaggerPreviewToggle" },
  build = "npm i",
  config = true,
}
