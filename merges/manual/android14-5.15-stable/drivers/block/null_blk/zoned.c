if (WARN_ON_ONCE(!dev->zone_size_sects))
	return 0;
	if (dev->zone_size_sects_shift)
		return sect >> dev->zone_size_sects_shift;

	return div64_u64(sect, dev->zone_size_sects);
@@RESOLVED-HUNK@@
	if (!dev->zone_size) {
		pr_err("zone_size must be non-zero\n");
		return -EINVAL;
	}
@@RESOLVED-HUNK@@

