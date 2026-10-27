vim.api.nvim_create_autocmd("PackChanged", {
  callback = function(ev)
    local cmd = ev.data.spec.data and ev.data.spec.data.build
    if cmd and (ev.data.kind == "install" or ev.data.kind == "update") then
      vim.system({ "sh", "-c", cmd }, { cwd = ev.data.path })
    end
  end,
})

local plugins = {
    "https://github.com/nvim-lua/plenary.nvim",
    "https://github.com/nvim-telescope/telescope.nvim",
    "https://github.com/nvim-treesitter/nvim-treesitter",
    "https://github.com/tpope/vim-fugitive",
    "https://github.com/christoomey/vim-tmux-navigator",
    "https://github.com/neovim/nvim-lspconfig",
    "https://github.com/hrsh7th/nvim-cmp",
    "https://github.com/hrsh7th/cmp-nvim-lsp",
    "https://github.com/L3MON4D3/LuaSnip",
    "https://github.com/nvim-lualine/lualine.nvim",
	{
		src = "https://github.com/nvim-telescope/telescope-fzf-native.nvim",
		data = { build = "make" }
	},
	{
		src = "https://github.com/catppuccin/nvim",
		name = "catppuccin"
	},
	{
		src = "https://github.com/ThePrimeagen/harpoon",
		version = "harpoon2"
	}
}

vim.pack.add(plugins)

for _, plugin in ipairs(plugins) do
	local src = type(plugin) == "table" and (plugin.name or plugin.src) or plugin
	local name = plugin.name or vim.fn.fnamemodify(src, ":t:r")
	pcall(vim.cmd.packadd, name)
end

require("telescope").setup({ extensions = { fzf = { fuzzy = true } } })
pcall(require("telescope").load_extension, "fzf")
