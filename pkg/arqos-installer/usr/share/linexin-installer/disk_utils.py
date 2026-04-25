#!/usr/bin/env python3

import re
import os

class DiskUtils:
    """Utility class for handling disk and partition naming across different disk types"""
    
    @staticmethod
    def parse_disk_path(device_path):
        """
        Parse a disk/partition path and return disk info.
        
        Args:
            device_path: Full path like /dev/sda1, /dev/nvme0n1p2, /dev/mmcblk0p1
            
        Returns:
            dict with:
                - device: original device path
                - base_disk: base disk path (e.g., /dev/sda, /dev/nvme0n1)
                - partition_num: partition number or None if whole disk
                - disk_type: 'sata', 'nvme', 'virtio', 'mmc', 'loop', etc.
                - disk_name: base name without /dev/ (e.g., sda, nvme0n1)
        """
        if not device_path or not device_path.startswith('/dev/'):
            return None
            
        # Remove /dev/ prefix for analysis
        device_name = device_path.replace('/dev/', '')
        
        result = {
            'device': device_path,
            'base_disk': None,
            'partition_num': None,
            'disk_type': None,
            'disk_name': None
        }
        
        # NVMe drives: /dev/nvme[0-9]+n[0-9]+(p[0-9]+)?
        nvme_match = re.match(r'^(nvme\d+n\d+)(p(\d+))?$', device_name)
        if nvme_match:
            result['disk_type'] = 'nvme'
            result['disk_name'] = nvme_match.group(1)
            result['base_disk'] = f'/dev/{nvme_match.group(1)}'
            if nvme_match.group(3):  # Has partition number
                result['partition_num'] = int(nvme_match.group(3))
            return result
        
        # MMC/SD cards: /dev/mmcblk[0-9]+(p[0-9]+)?
        mmc_match = re.match(r'^(mmcblk\d+)(p(\d+))?$', device_name)
        if mmc_match:
            result['disk_type'] = 'mmc'
            result['disk_name'] = mmc_match.group(1)
            result['base_disk'] = f'/dev/{mmc_match.group(1)}'
            if mmc_match.group(3):  # Has partition number
                result['partition_num'] = int(mmc_match.group(3))
            return result
        
        # Loop devices: /dev/loop[0-9]+(p[0-9]+)?
        loop_match = re.match(r'^(loop\d+)(p(\d+))?$', device_name)
        if loop_match:
            result['disk_type'] = 'loop'
            result['disk_name'] = loop_match.group(1)
            result['base_disk'] = f'/dev/{loop_match.group(1)}'
            if loop_match.group(3):  # Has partition number
                result['partition_num'] = int(loop_match.group(3))
            return result
        
        # VirtIO devices: /dev/vd[a-z]+[0-9]*
        virtio_match = re.match(r'^(vd[a-z]+)(\d+)?$', device_name)
        if virtio_match:
            result['disk_type'] = 'virtio'
            result['disk_name'] = virtio_match.group(1)
            result['base_disk'] = f'/dev/{virtio_match.group(1)}'
            if virtio_match.group(2):  # Has partition number
                result['partition_num'] = int(virtio_match.group(2))
            return result
        
        # SATA/IDE/SCSI devices: /dev/sd[a-z]+[0-9]*
        sata_match = re.match(r'^(sd[a-z]+)(\d+)?$', device_name)
        if sata_match:
            result['disk_type'] = 'sata'
            result['disk_name'] = sata_match.group(1)
            result['base_disk'] = f'/dev/{sata_match.group(1)}'
            if sata_match.group(2):  # Has partition number
                result['partition_num'] = int(sata_match.group(2))
            return result
        
        # IDE legacy devices: /dev/hd[a-z]+[0-9]*
        ide_match = re.match(r'^(hd[a-z]+)(\d+)?$', device_name)
        if ide_match:
            result['disk_type'] = 'ide'
            result['disk_name'] = ide_match.group(1)
            result['base_disk'] = f'/dev/{ide_match.group(1)}'
            if ide_match.group(2):  # Has partition number
                result['partition_num'] = int(ide_match.group(2))
            return result
        
        # Unknown device type - try generic parsing
        # Assume anything ending in digits is a partition
        generic_match = re.match(r'^([a-z]+\d*[a-z]*)(\d+)$', device_name)
        if generic_match:
            result['disk_type'] = 'unknown'
            result['disk_name'] = generic_match.group(1)
            result['base_disk'] = f'/dev/{generic_match.group(1)}'
            result['partition_num'] = int(generic_match.group(2))
            return result
        
        # No partition number - this is a whole disk
        result['disk_type'] = 'unknown'
        result['disk_name'] = device_name
        result['base_disk'] = device_path
        
        return result
    
    @staticmethod
    def get_partition_path(base_disk, partition_num):
        """
        Construct a partition path given a base disk and partition number.
        
        Args:
            base_disk: Base disk path (e.g., /dev/sda, /dev/nvme0n1)
            partition_num: Partition number
            
        Returns:
            Full partition path
        """
        if not base_disk or not partition_num:
            return None
            
        disk_info = DiskUtils.parse_disk_path(base_disk)
        if not disk_info:
            return None
            
        disk_type = disk_info['disk_type']
        disk_name = disk_info['disk_name']
        
        # NVMe, MMC, and loop devices use 'p' prefix for partitions
        if disk_type in ['nvme', 'mmc', 'loop']:
            return f'/dev/{disk_name}p{partition_num}'
        
        # SATA, IDE, VirtIO use direct numbering
        elif disk_type in ['sata', 'ide', 'virtio']:
            return f'/dev/{disk_name}{partition_num}'
        
        # Unknown - guess based on whether base ends with digit
        elif re.search(r'\d$', disk_name):
            return f'/dev/{disk_name}p{partition_num}'
        else:
            return f'/dev/{disk_name}{partition_num}'
    
    @staticmethod
    def is_whole_disk(device_path):
        """Check if a device path represents a whole disk or a partition"""
        disk_info = DiskUtils.parse_disk_path(device_path)
        return disk_info and disk_info['partition_num'] is None