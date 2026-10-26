import yaml,sys
w=yaml.safe_load(open(sys.argv[1]))
for j in w['jobs'].values():
    for s in j.get('steps',[]):
        if s.get('name')==sys.argv[2]: print(s['run'])
