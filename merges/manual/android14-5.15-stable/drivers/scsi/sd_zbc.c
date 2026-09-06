/* Whether or not a SCSI zone descriptor describes a gap zone. */
static bool sd_zbc_is_gap_zone(const u8 buf[64])
{
	return (buf[0] & 0xf) == ZBC_ZONE_TYPE_GAP;
}

/**
 * sd_zbc_parse_report - Parse a SCSI zone descriptor
 * @sdkp: SCSI disk pointer.
 * @buf: SCSI zone descriptor.
 * @idx: Index of the zone relative to the first zone reported by the current
 *	sd_zbc_report_zones() call.
 * @cb: Callback function pointer.
 * @data: Second argument passed to @cb.
 *
 * Return: Value returned by @cb.
 *
 * Convert a SCSI zone descriptor into struct blk_zone format. Additionally,
 * call @cb(blk_zone, @data).
 */
static int sd_zbc_parse_report(struct scsi_disk *sdkp, const u8 buf[64],
@@RESOLVED-HUNK@@
	while (zone_idx < nr_zones && lba < sdkp->capacity) {
		ret = sd_zbc_do_report_zones(sdkp, buf, buflen, lba, true);
		if (ret && zone_idx) {
			sd_printk(KERN_WARNING, sdkp,
				  "ZBC violation: %llu LBAs are not associated with a zone (zone length %llu)\n",
				  sdkp->capacity - lba, zone_length);
			sdkp->capacity = lba;
			set_capacity_and_notify(disk,
				logical_to_sectors(sdkp->device,
						   sdkp->capacity));
			ret = 0;
			break;
		}
@@RESOLVED-HUNK@@

@@RESOLVED-HUNK@@
		return 0;
	}

	/* Host-managed */
	sdkp->urswrz = buf[4] & 1;
	sdkp->zones_optimal_open = 0;
	sdkp->zones_optimal_nonseq = 0;
	sdkp->zones_max_open = get_unaligned_be32(&buf[16]);
	/* Check zone alignment method */
	switch (buf[23] & 0xf) {
	case 0:
	case ZBC_CONSTANT_ZONE_LENGTH:
		/* Use zone length */
		break;
	case ZBC_CONSTANT_ZONE_START_OFFSET:
		zone_starting_lba_gran = get_unaligned_be64(&buf[24]);
		if (zone_starting_lba_gran == 0 ||
		    !is_power_of_2(zone_starting_lba_gran) ||
		    logical_to_sectors(sdkp->device, zone_starting_lba_gran) >
		    UINT_MAX) {
			sd_printk(KERN_ERR, sdkp,
				  "Invalid zone starting LBA granularity %llu\n",
				  zone_starting_lba_gran);
			return -ENODEV;
		}
		sdkp->zone_starting_lba_gran = zone_starting_lba_gran;
		break;
	default:
		sd_printk(KERN_ERR, sdkp, "Invalid zone alignment method\n");
		return -ENODEV;
@@RESOLVED-HUNK@@
	div64_u64_rem(sdkp->capacity, sdkp->zone_info.zone_blocks, &remainder);
	if (remainder)
