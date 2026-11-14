/*
 * Eeprom.c
 *
 *  Created on: 2025年11月30日
 *      Author: lenovo
 */

#include "zf_common_headfile.h"

void Init_Parameter(void)
{
    flash_init();
    
    flash_buffer_clear();                                                       //先清空缓存区
    if(flash_check(FLASH_SECTION_INDEX, FLASH_PAGE_INDEX))                      // 判断flash是否有数据
    {
         flash_read_page_to_buffer(FLASH_SECTION_INDEX, FLASH_PAGE_INDEX, 7);   // 将数据从 flash 读取到缓冲区
    }
}

void Protect_Parameter(void)//将参数保存进flash
{
    if(flash_check(FLASH_SECTION_INDEX, FLASH_PAGE_INDEX))                      // 判断是否有数据
        flash_erase_page(FLASH_SECTION_INDEX, FLASH_PAGE_INDEX);                // 擦除这一页
    flash_write_page_from_buffer(FLASH_SECTION_INDEX, FLASH_PAGE_INDEX, 7);     // 向指定 Flash 扇区的页码写入缓冲区数据
}


