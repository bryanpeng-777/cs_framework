.PHONY: install-hooks check-hooks

install-hooks:
	@echo "正在安装 git hooks..."
	@git config core.hooksPath scripts/hooks
	@mkdir -p scripts/hooks
	@cp scripts/post-commit.sh scripts/hooks/post-commit
	@chmod +x scripts/hooks/post-commit
	@echo "✅ git hooks 安装完成（core.hooksPath = scripts/hooks）"

check-hooks:
	@if git config core.hooksPath > /dev/null 2>&1; then \
		echo "✅ hooks 已安装：$(git config core.hooksPath)"; \
	else \
		echo "⚠️  hooks 未安装，请运行: make install-hooks"; \
	fi
