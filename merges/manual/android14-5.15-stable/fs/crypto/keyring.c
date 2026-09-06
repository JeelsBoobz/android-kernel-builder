	WARN_ON_ONCE(refcount_read(&mk->mk_active_refs) != 0);
	clear_mk_users(mk);
@@RESOLVED-HUNK@@
/* Find the current user's claim in ->mk_users.  ->mk_sem must be held. */
static struct fscrypt_master_key_user *
find_master_key_user(struct fscrypt_master_key *mk)
{
	struct fscrypt_master_key_user *mk_user;
	kuid_t uid = current_fsuid();

	list_for_each_entry(mk_user, &mk->mk_users, link) {
		if (uid_eq(mk_user->uid, uid))
			return mk_user;
