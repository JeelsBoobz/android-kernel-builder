/* Whether or not a SCSI zone descriptor describes a gap zone. */
static bool sd_zbc_is_gap_zone(const u8 buf[64])
{
	return (buf[0] & 0xf) == ZBC_ZONE_TYPE_GAP;
}

@@RESOLVED-THEIRS@@
@@RESOLVED-HUNK@@@@RESOLVED-OURS@@
@@RESOLVED-HUNK@@@@RESOLVED-OURS@@
@@RESOLVED-HUNK@@@@RESOLVED-OURS@@
@@RESOLVED-HUNK@@@@RESOLVED-OURS@@
