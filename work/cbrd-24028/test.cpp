#include "extensible_array.hpp"

int main()
{
	const std::size_t AVAILABLE_STACK_DEFAULT_SIZE = 1;
	cubmem::appendable_array<int, AVAILABLE_STACK_DEFAULT_SIZE> available_stack;
	
	int values[5] = { 1, 2, 3, 4, 5 };
	int *value = NULL;
	const int *ptr = NULL;
	
	for (int i = 0; i < 5; i++)
	{
		value = &values[i];
		available_stack.append (value, 1);
		printf("[%d/5] available_stack.get_memsize(): %lu", i, available_stack.get_memsize());
		ptr = available_stack.get_array();
	}

	return 0;
}
