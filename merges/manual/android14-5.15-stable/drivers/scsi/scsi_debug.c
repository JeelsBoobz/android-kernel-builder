	ZBC_ZTYPE_CNV	= 0x1,
	ZBC_ZTYPE_SWR	= 0x2,
	ZBC_ZTYPE_SWP	= 0x3,
	/* ZBC_ZTYPE_SOBR = 0x4, */
	ZBC_ZTYPE_GAP	= 0x5,
@@RESOLVED-HUNK@@
	return zsp->z_type == ZBC_ZTYPE_CNV;
}

static inline bool zbc_zone_is_gap(struct sdeb_zone_state *zsp)
{
	return zsp->z_type == ZBC_ZTYPE_GAP;
}

static inline bool zbc_zone_is_seq(struct sdeb_zone_state *zsp)
{
	return !zbc_zone_is_conv(zsp) && !zbc_zone_is_gap(zsp);
@@RESOLVED-HUNK@@
	max_zones = devip->nr_zones - (zs_lba >> devip->zsize_shift);
	rep_max_zones = (ALIGN((u64)alloc_len, RZONES_DESC_HD) - RZONES_DESC_HD) >>
			ilog2(RZONES_DESC_HD);
	rep_max_zones = min_t(unsigned int, rep_max_zones, max_zones);
	arr_len = (u64)RZONES_DESC_HD * (rep_max_zones + 1);
