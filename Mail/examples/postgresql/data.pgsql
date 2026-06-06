-- domains
insert into virtual_domains(name) values('example.org');

-- user info
insert into virtual_users (domain_id, password, salt, email) values (
  1,
  ssha512('psaaword', 'ffffff'),
  'ffffff',
  'user1@example.org'
);

-- virtual_aliases
insert into virtual_aliases(domain_id,source,destination) values (1,'user2@example.org','user1@example.org');
