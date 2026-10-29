-- Rex 設定:快捷鍵沿用 ghostty 的 cmd+s 前綴(../ghostty/config),
-- herdr 才有的功能(close tab、sidebar、popup)也掛在同一個前綴下(../herdr.nix)。
-- 驗證:rex config check;home-manager switch 後會自動 rex config reload。
-- 注意:在 app 用 Change Shortcut… 設的快捷鍵優先於本檔。

local terminal = "com.superlogical.terminal"

-- config
rex.bind("cmd+s>r", "client.config.reload")
rex.bind("cmd+s>q", "pane.close")

-- zoom
rex.bind("cmd+s>shift+=", "client.font.increase")
rex.bind("cmd+s>shift+-", "client.font.decrease")
rex.bind("cmd+s>shift+r", "client.font.reset")

-- split
rex.bind("cmd+s>\\", "pane.split", { direction = "right" })
rex.bind("cmd+s>-", "pane.split", { direction = "down" })
rex.bind("cmd+s>e", "pane.balance")

-- split navigation
rex.bind("cmd+s>h", "pane.focus", { direction = "left" })
rex.bind("cmd+s>j", "pane.focus", { direction = "down" })
rex.bind("cmd+s>k", "pane.focus", { direction = "up" })
rex.bind("cmd+s>l", "pane.focus", { direction = "right" })

rex.bind("cmd+s>z", "pane.zoom")

-- resize mode:hjkl 移動分隔線,shift 加大步幅,e 平均,esc/enter 離開。
-- mode 內的鍵和外面的 cmd+s>hjkl 互不影響;exclusive 讓其他鍵(含 cmd+s 序列)
-- 在 mode 內不作用,避免誤打進終端。cmd+s>r 已給 reload,入口用 m(ode)。
rex.mode("resize", { exclusive = true })
rex.bind("cmd+s>m", "client.mode.enter", { name = "resize" })
for _, k in ipairs({ { "h", "left" }, { "j", "down" }, { "k", "up" }, { "l", "right" } }) do
	rex.bind("resize/" .. k[1], "pane.resize", { direction = k[2] })
	rex.bind("resize/shift+" .. k[1], "pane.resize", { direction = k[2], amount = 15 })
end
rex.bind("resize/e", "pane.balance")
rex.bind("resize/enter", "client.mode.exit")

-- tab
rex.bind("cmd+s>t", "client.tab.new")
rex.bind("cmd+s>shift+q", "client.tab.close") -- herdr close_tab
rex.bind("cmd+s>]", "client.tab.next")
rex.bind("cmd+s>[", "client.tab.previous")
rex.bind("cmd+s>,", "client.tab.move.backward")
rex.bind("cmd+s>.", "client.tab.move.forward")

-- tab navigation
for i = 1, 9 do
	rex.bind("cmd+s>" .. i, "client.tab.goto", { index = i })
end

-- session:對應 herdr 的 spaces 與 sidebar
rex.bind("cmd+s>s", "session.switch")
rex.bind("cmd+s>b", "client.sidebar.toggle")

-- command palette
rex.bind("cmd+s>p", "client.palette.toggle")

-- search
rex.bind("cmd+s>/", "client.find.open")
rex.bind("cmd+s>n", "client.find.next")
rex.bind("cmd+s>shift+n", "client.find.previous")

-- popup:對應 herdr 的 popup 與 ghostty 的 quick terminal。
-- 在目前 tab 上開 80% 浮動層,cwd 跟著 focused pane,程式結束就關閉。
-- 用 process 的 cwd 而非 pwd:zsh 沒回報 OSC 7 時 pwd 是空的。
rex.action({
	name = "popup",
	title = "Open Popup",
	description = "Open a floating terminal over the current tab; without a command it runs a shell.",
	args = { command = "array?" },
	run = function(ctx, args)
		local cwd
		if ctx.block_id ~= nil then
			local p = rex.block.call(terminal, "process", { block_id = ctx.block_id })
			cwd = p and p.foreground and p.foreground.cwd
		end
		local _, err = rex.session.new_layer({
			bounds = { 0.1, 0.1, 0.8, 0.8 },
			focus = true,
			layout = rex.layout.block({
				flavor = terminal .. ".shell",
				options = { command = args.command, cwd = cwd },
			}),
		})
		if err ~= nil then
			error(err, 0)
		end
	end,
})

rex.bind("cmd+s>`", "popup")
rex.bind("cmd+s>g", "popup", { command = { "lazygit" } })
rex.bind("cmd+s>d", "popup", { command = { "lazydocker" } })
rex.bind("cmd+s>y", "popup", { command = { "yazi" } })
