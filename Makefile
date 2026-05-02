.PHONY: up reset logs

up:
	docker compose up -d --wait

reset:
	docker compose down
	-docker run --rm -v "$(CURDIR)/storage:/data" alpine sh -c "rm -rf /data/*"
	rm -f shared/install.done
	docker compose up -d --wait

logs:
	docker compose logs -f
