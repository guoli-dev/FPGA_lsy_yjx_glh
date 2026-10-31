/*
 * Eeprom.h
 *
 *  Created on: 2025年11月30日
 *      Author: lenovo
 */

#ifndef CODE_EEPROM_H_
#define CODE_EEPROM_H_

#define FLASH_SECTION_INDEX       (0)                                 // 存储数据用的扇区
#define FLASH_PAGE_INDEX          (0)                                // 存储数据用的页码 倒数第一个页码

void Init_Parameter(void);
void Protect_Parameter(void);

#endif /* CODE_EEPROM_H_ */
