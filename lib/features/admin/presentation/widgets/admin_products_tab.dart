import 'package:marketflow/features/catalog/domain/entities/product_model.dart';
import 'package:flutter/material.dart';

class AdminProductsTab extends StatelessWidget {
  const AdminProductsTab({
    super.key,
    required this.loadingProducts,
    required this.products,
    required this.submitting,
    required this.searchController,
    required this.categories,
    required this.selectedCategory,
    required this.exportingStock,
    required this.onSearch,
    required this.onCategoryChanged,
    required this.onOpenCategoryManager,
    required this.onExportStock,
    required this.onOpenStockEditor,
    required this.onManageDiscount,
    required this.onEditProduct,
    required this.onDeleteProduct,
    required this.subtitleBuilder,
  });

  final bool loadingProducts;
  final List<Product> products;
  final bool submitting;
  final TextEditingController searchController;
  final List<String> categories;
  final String selectedCategory;
  final bool exportingStock;
  final Future<void> Function() onSearch;
  final ValueChanged<String?> onCategoryChanged;
  final VoidCallback onOpenCategoryManager;
  final VoidCallback onExportStock;
  final void Function(Product product) onOpenStockEditor;
  final void Function(Product product) onManageDiscount;
  final void Function(Product product) onEditProduct;
  final void Function(Product product) onDeleteProduct;
  final String Function(Product product) subtitleBuilder;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search products...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () async {
                  await onSearch();
                },
                icon: const Icon(Icons.arrow_forward),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onSubmitted: (_) async {
              await onSearch();
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 560;
              final categoryFilter = DropdownButtonFormField<String>(
                key: ValueKey<String>('product_category_$selectedCategory'),
                initialValue: selectedCategory,
                decoration: const InputDecoration(
                  labelText: 'Category Filter',
                  border: OutlineInputBorder(),
                ),
                items: categories
                    .map(
                      (category) => DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      ),
                    )
                    .toList(),
                onChanged: onCategoryChanged,
              );

              final categoryButton = OutlinedButton.icon(
                onPressed: onOpenCategoryManager,
                icon: const Icon(Icons.category_outlined),
                label: const Text('Categories'),
              );

              if (compact) {
                return Column(
                  children: [
                    categoryFilter,
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: categoryButton),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: categoryFilter),
                  const SizedBox(width: 8),
                  categoryButton,
                ],
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.centerLeft,
            child: ElevatedButton.icon(
              onPressed: exportingStock ? null : onExportStock,
              icon: exportingStock
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(
                exportingStock ? 'Exporting...' : 'Export Stock Excel',
              ),
            ),
          ),
        ),
        Expanded(
          child: loadingProducts
              ? const Center(child: CircularProgressIndicator())
              : products.isEmpty
              ? const Center(child: Text('No products found'))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    final actions = Wrap(
                      spacing: 2,
                      children: [
                        IconButton(
                          onPressed: submitting
                              ? null
                              : () => onOpenStockEditor(product),
                          icon: const Icon(Icons.inventory_outlined),
                        ),
                        IconButton(
                          onPressed: submitting
                              ? null
                              : () => onManageDiscount(product),
                          icon: const Icon(Icons.local_offer_outlined),
                        ),
                        IconButton(
                          onPressed: submitting
                              ? null
                              : () => onEditProduct(product),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          onPressed: submitting
                              ? null
                              : () => onDeleteProduct(product),
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    );

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final compact = constraints.maxWidth < 560;
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(subtitleBuilder(product)),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: actions,
                                ),
                              ],
                            );
                          }

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(subtitleBuilder(product)),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              actions,
                            ],
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
