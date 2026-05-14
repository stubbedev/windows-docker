.PHONY: up redeploy reset logs

# Bring the container up (or resume) and wait for the dispatcher
# to write shared/install.done.
up:
	docker compose up -d --wait

# Force a re-deploy: reboot Windows so the OEM-Dispatcher fires
# again. Phase-base is skipped (marker on disk); phase-php re-runs
# only if shared/.runtime/php-config.ini hash changed; phase-code
# re-runs only if shared/.runtime/post-install.bat hash changed.
redeploy:
	rm -f shared/install.done
	docker compose restart windows
	docker compose up -d --wait

# Tear down the VM disk entirely; next `make up` rebuilds Windows
# from scratch (15-30 min) and re-runs every phase.
reset:
	docker compose down
	-docker run --rm -v "$(CURDIR)/storage:/data" alpine sh -c "rm -rf /data/*"
	rm -f shared/install.done
	docker compose up -d --wait

logs:
	docker compose logs -f
