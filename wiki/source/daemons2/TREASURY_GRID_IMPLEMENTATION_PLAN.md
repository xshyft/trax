# Treasury Activity Grid - Complete Implementation Plan

## Current Status
✅ Backend returns `created_at` timestamp (ISO8601)
✅ Number formatting utility with thousand separators
✅ Date formatting utility
✅ Backend pagination state added to TreasuryActivity page
⚠️  Grid component needs complete rewrite for backend integration

## Required Implementation

### 1. TreasuryActivityGridView Component Rewrite

**Props Interface:**
```typescript
interface TreasuryActivityGridViewProps {
  data: EventLog[];
  total: number;
  isLoading: boolean;
  currentPage: number;
  pageSize: number;
  totalPages: number;
  onPageChange: (page: number) => void;
  onPageSizeChange: (size: number) => void;
  searchQuery: string;
  onSearchChange: (query: string) => void;
  sortBy: string;
  sortDirection: 'asc' | 'desc';
  onSortChange: (column: string, direction: 'asc' | 'desc') => void;
  emptyMessage: string;
}
```

**ALL Columns to Include:**
1. ✅ Event Name (with icon)
2. ✅ Block Number (formatted with commas)
3. ✅ Token Symbol/Name
4. ✅ From Account (IID + name)
5. ✅ To Account (IID + name)
6. ✅ Amount (formatted with commas + symbol)
7. ❌ **Created At** (timestamp with date/time)
8. ❌ **IID** (full event log IID)
9. ❌ **Log Index** (number)
10. ❌ **Transaction Hash** (full, copyable)
11. ❌ **Contract Address** (full, copyable)
12. ✅ Chain ID

**Features:**
- ✅ Column visibility toggles
- ✅ Column sorting (delegates to backend via onSortChange)
- ❌ **Backend Search** (global search via searchQuery prop)
- ❌ **Backend Pagination** (offset-based via currentPage/pageSize)
- ✅ Column resizing
- ✅ Row expansion for details
- ❌ **Pagination Controls** (prev/next/page selector)
- ❌ **Page Size Selector** (10, 25, 50, 100, 200)

### 2. Backend Filtering (Currently Missing)

**Current Limitation:**
- API only supports ONE global `search` parameter
- No column-specific filtering
- No date range filtering

**To Add Column-Specific Filtering:**
Would need backend API changes to accept:
```
?filter_event_name=Transfer
&filter_block_min=1000
&filter_block_max=2000
&filter_created_after=2025-01-01T00:00:00Z
&filter_created_before=2025-12-31T23:59:59Z
```

**Current Workaround:**
Use global `search` parameter which searches across all text fields.

### 3. Cursor-Based Pagination

**Current:** Offset-based (page 1, 2, 3...)
**To Add Cursor-Based:**

Would need backend changes:
- Add `cursor` field to ListEventLogsResponse
- Support `?cursor=xxx` query parameter
- Return `next_cursor` and `prev_cursor` in response

**Benefits:**
- Better performance for large datasets
- Consistent results during concurrent writes
- No "skipped rows" issue with offset pagination

### 4. Date/Time Features

**Display Format:**
- Absolute: "2025-11-02 12:34:56"
- Relative: "2h ago", "3d ago"

**Filtering:**
- Date range picker component
- Presets: Today, Last 7 days, Last 30 days, Custom range

**Implementation:**
```typescript
// Column definition for created_at
{
  id: 'created_at',
  header: 'Created',
  accessor: (row) => row.created_at,
  sortable: true,
  renderCell: (value) => (
    <div className="flex flex-col">
      <span className="text-slate-300 text-sm">
        {formatDate(value)}
      </span>
      <span className="text-slate-500 text-xs">
        {formatRelativeTime(value)}
      </span>
    </div>
  )
}
```

## Implementation Priority

### Phase 1: Core Grid (IN PROGRESS)
- [x] Add pagination state to page
- [x] Pass pagination props to grid
- [ ] Rewrite grid to use backend pagination
- [ ] Add all columns with proper formatting
- [ ] Add pagination controls UI

### Phase 2: Enhanced Features
- [ ] Add search debouncing (500ms delay)
- [ ] Add loading states per column
- [ ] Add column sorting indicators
- [ ] Add keyboard navigation

### Phase 3: Backend Enhancements (Requires Go changes)
- [ ] Add column-specific filtering to API
- [ ] Add date range filtering to API
- [ ] Add cursor-based pagination to API
- [ ] Add field selection (sparse fieldsets)

## File Structure

```
src/
├── components/
│   ├── TreasuryActivityGridView.tsx     # Main grid component
│   ├── GridPagination.tsx               # Reusable pagination controls
│   ├── GridColumnSelector.tsx           # Column visibility UI
│   └── DateRangeFilter.tsx              # Date range picker
├── utils/
│   ├── formatNumber.ts                   # ✅ Done
│   ├── formatDate.ts                     # ✅ Done
│   └── debounce.ts                       # TODO
└── pages/
    └── TreasuryActivity.tsx              # ✅ Updated with pagination state
```

## Notes

- Filters are BACKEND (server-side) after this implementation
- Pagination is BACKEND (offset-based)
- Cursor pagination requires backend API changes
- Column-specific filters require backend API changes
- All numbers display with thousand separators
- Timestamps show both absolute and relative time
