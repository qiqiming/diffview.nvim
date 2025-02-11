local oop = require("diffview.oop")
local utils = require("diffview.utils")
local FileEntry = require("diffview.views.file_entry").FileEntry
local RevType = require("diffview.git.rev").RevType
local api = vim.api

local M = {}

---@class CFileEntry : FileEntry
---@field left_null boolean
---@field right_null boolean
---@field get_file_data function
local CFileEntry = oop.create_class("CFileEntry", FileEntry)

---CFileEntry constructor.
---@param opt any
---@return CFileEntry
function CFileEntry:init(opt)
  self.super:init(opt)
  self.left_binary = opt.left_binary
  self.right_binary = opt.right_binary
  self.left_null = opt.left_null
  self.right_null = opt.right_null
  self.get_file_data = opt.get_file_data
end

---@Override
function CFileEntry:load_buffers(git_root, left_winid, right_winid)
  local splits = {
    {
      winid = left_winid,
      bufid = self.left_bufid,
      rev = self.left,
      pos = "left",
      lines = self.get_file_data(self.kind, self.path, "left"),
      null = self.left_null == true,
    },
    {
      winid = right_winid,
      bufid = self.right_bufid,
      rev = self.right,
      pos = "right",
      lines = self.get_file_data(self.kind, self.path, "right"),
      null = self.right_null == true,
    },
  }

  utils.no_win_event_call(function()
    for _, split in ipairs(splits) do
      if not (split.bufid and api.nvim_buf_is_loaded(split.bufid)) then
        if split.rev.type == RevType.LOCAL then
          if split.null or CFileEntry.should_null(split.rev, self.status, split.pos) then
            local bn = CFileEntry._create_buffer(git_root, split.rev, self.path, split.lines, true)
            api.nvim_win_set_buf(split.winid, bn)
            split.bufid = bn
          else
            api.nvim_win_call(split.winid, function()
              vim.cmd("edit " .. vim.fn.fnameescape(self.absolute_path))
              split.bufid = api.nvim_get_current_buf()
            end)
          end
        elseif
          vim.tbl_contains({ RevType.COMMIT, RevType.INDEX, RevType.CUSTOM }, split.rev.type)
        then
          local bn
          if self.oldpath and split.pos == "left" then
            bn = CFileEntry._create_buffer(
              git_root,
              split.rev,
              self.oldpath,
              split.lines,
              split.null
            )
          else
            bn = CFileEntry._create_buffer(
              git_root,
              split.rev,
              self.path,
              split.lines,
              split.null or CFileEntry.should_null(split.rev, self.status, split.pos)
            )
          end
          table.insert(self.created_bufs, bn)
          api.nvim_win_set_buf(split.winid, bn)
          split.bufid = bn
          api.nvim_win_call(split.winid, function()
            vim.cmd("filetype detect")
          end)
        end

        CFileEntry._attach_buffer(split.bufid)
      else
        api.nvim_win_set_buf(split.winid, split.bufid)
        CFileEntry._attach_buffer(split.bufid)
      end
    end
  end)

  self.left_bufid = splits[1].bufid
  self.right_bufid = splits[2].bufid

  CFileEntry._update_windows(left_winid, right_winid)
  vim.cmd("do WinEnter")
end

---@static
---@Override
function CFileEntry._create_buffer(git_root, rev, path, lines, null)
  if null or not lines then
    return CFileEntry._get_null_buffer()
  end

  local bn = api.nvim_create_buf(false, false)
  api.nvim_buf_set_lines(bn, 0, -1, false, lines)

  local context
  if rev.type == RevType.COMMIT then
    context = rev:abbrev()
  elseif rev.type == RevType.INDEX then
    context = ":0:"
  elseif rev.type == RevType.CUSTOM then
    context = "[diff]"
  end

  -- stylua: ignore
  local fullname = utils.path_join({ "diffview://", git_root, ".git", context, path, })
  for option, value in pairs(FileEntry.bufopts) do
    api.nvim_buf_set_option(bn, option, value)
  end

  local ok = pcall(api.nvim_buf_set_name, bn, fullname)
  if not ok then
    -- Resolve name conflict
    local i = 1
    while not ok do
      -- stylua: ignore
      fullname = utils.path_join({ "diffview://", git_root, ".git", context, i, path, })
      ok = pcall(api.nvim_buf_set_name, bn, fullname)
      i = i + 1
    end
  end

  return bn
end

M.CFileEntry = CFileEntry
return M
