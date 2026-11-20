# Operation constraints and rules

This document make an inventory of constraints and operation rules of
the puppet-magic_castle environment.

## Identity and naming rules

- Never reuse a deleted project group name for another project. This includes
  renaming another group to the deleted name and creation through automation.
- Never reassign a username to a different person. Retain retired usernames in
  the site's identity inventory so operators and automation can reject reuse.
- Do not rename managed users or project groups as a routine operation. These
  services do not provide a complete migration of paths and Slurm identities.
- Do not manually reuse a UID or GID while files, ACLs, or other resources still
  refer to it. Deleting a directory entry does not remove numeric ownership from
  filesystems.
- Record retired usernames, group names, UID/GID values, home paths, project
  paths, Slurm account names, retirement dates, and data disposition.

These rules apply to operators, administrators, and automation. FreeIPA
permissions can restrict deletion and renaming for delegated operators, but this
guide does not imply that such restrictions are already configured. Keeping a
retired group under its original name reserves that name; after deletion, the
inventory must provide that reservation.

### Why names must not be recycled

A recreated project group can have a new GID while reconnecting to the previous
Slurm account by name. Existing Slurm allocation settings remain unless an
administrator changes them. A delayed deletion retry can also remove associations
and home symlinks belonging to the replacement project. Never reusing the group
name prevents that retry from targeting a replacement identity.

A recreated username can collide with an existing home, scratch directory, and
personal project directory. Home provisioning preserves existing files. Scratch
and project provisioning do not transfer an existing directory owned by an old,
non-root UID to a new UID. A different UID can therefore encounter inaccessible
directories; reusing the old UID can expose the previous person's data. Slurm
membership comparisons also use usernames and cannot distinguish those people.

## Project group membership

Project provisioning and Slurm account synchronization performed by `mkhome` and
`mkproject` support only users listed directly in a project group's LDAP `member`
attribute. Membership inherited through nested groups is unsupported. Add each
user directly to every project group for which they require provisioning and
Slurm account access.

Home and scratch directory creation are independent of this membership
restriction.
