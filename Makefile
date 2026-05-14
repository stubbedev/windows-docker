.PHONY: up redeploy reset logs logs-dispatcher

# Friendly check: docker compose's own interpolation error is cryptic
# when .env is missing. Catch it early.
define ENV_GUARD
@if [ ! -f .env ]; then \
	echo "ERROR: .env is missing. Run: cp .env.example .env"; \
	echo "Then edit WIN_PASSWORD before retrying."; \
	exit 1; \
fi
endef

# Bring the container up (or resume) and wait for the dispatcher
# to write shared/install.done.
up:
	$(ENV_GUARD)
	docker compose up -d --wait

# Force a re-deploy: reboot Windows so the OEM-Dispatcher fires
# again. Phase-base is skipped (marker on disk); phase-php re-runs
# only if shared/.runtime/php-config.ini hash changed; phase-code
# re-runs only if shared/.runtime/post-install.bat hash changed.
redeploy:
	$(ENV_GUARD)
	rm -f shared/install.done
	docker compose restart windows
	docker compose up -d --wait

# Tear down the VM disk entirely; next `make up` rebuilds Windows
# from scratch (15-30 min) and re-runs every phase.
reset:
	$(ENV_GUARD)
	docker compose down
	-docker run --rm -v "$(CURDIR)/storage:/data" alpine sh -c "rm -rf /data/*"
	rm -f shared/install.done
	rm -rf shared/.logs
	docker compose up -d --wait

logs:
	docker compose logs -f

# Tail the dispatcher log written by the VM to the SMB share.
logs-dispatcher:
	@if [ ! -f shared/.logs/dispatcher.log ]; then \
		echo "shared/.logs/dispatcher.log not yet written. Has the dispatcher run yet?"; \
		exit 0; \
	fi
	tail -f shared/.logs/dispatcher.log
