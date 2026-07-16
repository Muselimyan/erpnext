import yaml

with open('/home/vahe/frappe-compose.yml', 'r') as f:
    content = f.read()

data = yaml.safe_load(content)

for svc in ['db', 'redis-cache', 'redis-queue', 'cron']:
    data['services'][svc]['pull_policy'] = 'never'

with open('/home/vahe/frappe-compose.yml', 'w') as f:
    yaml.dump(data, f, default_flow_style=False, allow_unicode=True, sort_keys=False)

print('Done — pull_policy: never added to db, redis-cache, redis-queue, cron')
