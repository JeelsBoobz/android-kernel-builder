#ifdef CONFIG_BPF_SYSCALL
	RCU_INIT_POINTER(tsk->bpf_storage, NULL);
	tsk->bpf_ctx = NULL;
#endif
#ifdef CONFIG_ANDROID_VENDOR_OEM_DATA
	memset(&tsk->android_vendor_data1, 0, sizeof(tsk->android_vendor_data1));
	memset(&tsk->android_oem_data1, 0, sizeof(tsk->android_oem_data1));
#endif
	trace_android_vh_dup_task_struct(tsk, orig);
