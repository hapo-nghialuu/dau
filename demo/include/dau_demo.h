// C bridging header cho app macOS demo (Swift import các hàm demo_*).
#ifndef DAU_DEMO_H
#define DAU_DEMO_H
#include <stdint.h>

void demo_reset(void);
void demo_set_method(uint32_t vni);       // 0 = Telex, 1 = VNI
void demo_set_auto_cap(uint32_t on);
void demo_set_auto_restore(uint32_t on);
uint32_t demo_process(uint32_t ch);        // trả độ dài chuỗi đang soạn (UTF-8) trong buffer
uint32_t demo_on_break(uint32_t brk);      // trả độ dài text commit trong buffer
uint32_t demo_escape(void);                // trả độ dài raw trong buffer
const uint8_t *demo_buf_ptr(void);         // con trỏ buffer tĩnh

#endif
