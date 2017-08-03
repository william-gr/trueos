//===-- SearchFilter.h ------------------------------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//

#ifndef liblldb_SearchFilter_h_
#define liblldb_SearchFilter_h_

#include "lldb/Core/FileSpecList.h"
#include "lldb/Utility/StructuredData.h"

#include "lldb/Utility/FileSpec.h" // for FileSpec
#include "lldb/lldb-forward.h"     // for SearchFilterSP, TargetSP, Modu...

#include <stdint.h> // for uint32_t

namespace lldb_private {
class Address;
}
namespace lldb_private {
class Breakpoint;
}
namespace lldb_private {
class CompileUnit;
}
namespace lldb_private {
class Status;
}
namespace lldb_private {
class Function;
}
namespace lldb_private {
class ModuleList;
}
namespace lldb_private {
class SearchFilter;
}
namespace lldb_private {
class Stream;
}
namespace lldb_private {
class SymbolContext;
}
namespace lldb_private {
class Target;
}

namespace lldb_private {

//----------------------------------------------------------------------
/// @class Searcher SearchFilter.h "lldb/Core/SearchFilter.h"
/// @brief Class that is driven by the SearchFilter to search the
/// SymbolContext space of the target program.
//----------------------------------------------------------------------

//----------------------------------------------------------------------
/// General Outline:
/// Provides the callback and search depth for the SearchFilter search.
//----------------------------------------------------------------------

class Searcher {
public:
  typedef enum {
    eCallbackReturnStop = 0, // Stop the iteration
    eCallbackReturnContinue, // Continue the iteration
    eCallbackReturnPop       // Pop one level up and continue iterating
  } CallbackReturn;

  typedef enum {
    eDepthTarget,
    eDepthModule,
    eDepthCompUnit,
    eDepthFunction,
    eDepthBlock,
    eDepthAddress
  } Depth;

  Searcher();

  virtual ~Searcher();

  virtual CallbackReturn SearchCallback(SearchFilter &filter,
                                        SymbolContext &context, Address *addr,
                                        bool complete) = 0;

  virtual Depth GetDepth() = 0;

  //------------------------------------------------------------------
  /// Prints a canonical description for the searcher to the stream \a s.
  ///
  /// @param[in] s
  ///   Stream to which the output is copied.
  //------------------------------------------------------------------
  virtual void GetDescription(Stream *s);
};

//----------------------------------------------------------------------
/// @class SearchFilter SearchFilter.h "lldb/Core/SearchFilter.h"
/// @brief Class descends through the SymbolContext space of the target,
/// applying a filter at each stage till it reaches the depth specified by
/// the GetDepth method of the searcher, and calls its callback at that point.
//----------------------------------------------------------------------

//----------------------------------------------------------------------
/// General Outline:
/// Provides the callback and search depth for the SearchFilter search.
///
/// The search is done by cooperation between the search filter and the
/// searcher.
/// The search filter does the heavy work of recursing through the SymbolContext
/// space of the target program's symbol space.  The Searcher specifies the
/// depth
/// at which it wants its callback to be invoked.  Note that since the
/// resolution
/// of the Searcher may be greater than that of the SearchFilter, before the
/// Searcher qualifies an address it should pass it to "AddressPasses."
/// The default implementation is "Everything Passes."
//----------------------------------------------------------------------

class SearchFilter {
public:
  //------------------------------------------------------------------
  /// The basic constructor takes a Target, which gives the space to search.
  ///
  /// @param[in] target
  ///    The Target that provides the module list to search.
  //------------------------------------------------------------------
  SearchFilter(const lldb::TargetSP &target_sp);

  SearchFilter(const SearchFilter &rhs);

  SearchFilter(const lldb::TargetSP &target_sp, unsigned char filterType);

  virtual ~SearchFilter();

  SearchFilter &operator=(const SearchFilter &rhs);

  //------------------------------------------------------------------
  /// Call this method with a file spec to see if that spec passes the filter.
  ///
  /// @param[in] spec
  ///    The file spec to check against the filter.
  /// @return
  ///    \b true if \a spec passes, and \b false otherwise.
  //------------------------------------------------------------------
  virtual bool ModulePasses(const FileSpec &spec);

  //------------------------------------------------------------------
  /// Call this method with a Module to see if that module passes the filter.
  ///
  /// @param[in] module
  ///    The Module to check against the filter.
  ///
  /// @return
  ///    \b true if \a module passes, and \b false otherwise.
  //------------------------------------------------------------------
  virtual bool ModulePasses(const lldb::ModuleSP &module_sp);

  //------------------------------------------------------------------
  /// Call this method with a Address to see if \a address passes the filter.
  ///
  /// @param[in] addr
  ///    The address to check against the filter.
  ///
  /// @return
  ///    \b true if \a address passes, and \b false otherwise.
  //------------------------------------------------------------------
  virtual bool AddressPasses(Address &addr);

  //------------------------------------------------------------------
  /// Call this method with a FileSpec to see if \a file spec passes the filter
  /// as the name of a compilation unit.
  ///
  /// @param[in] fileSpec
  ///    The file spec to check against the filter.
  ///
  /// @return
  ///    \b true if \a file spec passes, and \b false otherwise.
  //------------------------------------------------------------------
  virtual bool CompUnitPasses(FileSpec &fileSpec);

  //------------------------------------------------------------------
  /// Call this method with a CompileUnit to see if \a comp unit passes the
  /// filter.
  ///
  /// @param[in] compUnit
  ///    The CompileUnit to check against the filter.
  ///
  /// @return
  ///    \b true if \a Comp Unit passes, and \b false otherwise.
  //------------------------------------------------------------------
  virtual bool CompUnitPasses(CompileUnit &compUnit);

  //------------------------------------------------------------------
  /// Call this method to do the search using the Searcher.
  ///
  /// @param[in] searcher
  ///    The searcher to drive with this search.
  ///
  //------------------------------------------------------------------
  virtual void Search(Searcher &searcher);

  //------------------------------------------------------------------
  /// Call this method to do the search using the Searcher in the module list
  /// \a modules.
  ///
  /// @param[in] searcher
  ///    The searcher to drive with this search.
  ///
  /// @param[in] modules
  ///    The module list within which to restrict the search.
  ///
  //------------------------------------------------------------------
  virtual void SearchInModuleList(Searcher &searcher, ModuleList &modules);

  //------------------------------------------------------------------
  /// This determines which items are REQUIRED for the filter to pass.
  /// For instance, if you are filtering by Compilation Unit, obviously
  /// symbols that have no compilation unit can't pass  So return
  /// eSymbolContextCU
  /// and search callbacks can then short cut the search to avoid looking at
  /// things that obviously won't pass.
  ///
  /// @return
  ///    The required elements for the search, which is an or'ed together
  ///    set of lldb:SearchContextItem enum's.
  ///
  //------------------------------------------------------------------
  virtual uint32_t GetFilterRequiredItems();

  //------------------------------------------------------------------
  /// Prints a canonical description for the search filter to the stream \a s.
  ///
  /// @param[in] s
  ///   Stream to which the output is copied.
  //------------------------------------------------------------------
  virtual void GetDescription(Stream *s);

  //------------------------------------------------------------------
  /// Standard "Dump" method.  At present it does nothing.
  //------------------------------------------------------------------
  virtual void Dump(Stream *s) const;

  lldb::SearchFilterSP CopyForBreakpoint(Breakpoint &breakpoint);

  static lldb::SearchFilterSP
  CreateFromStructuredData(Target &target,
                           const StructuredData::Dictionary &data_dict,
                           Status &error);

  virtual StructuredData::ObjectSP SerializeToStructuredData() {
    return StructuredData::ObjectSP();
  }

  static const char *GetSerializationKey() { return "SearchFilter"; }

  static const char *GetSerializationSubclassKey() { return "Type"; }

  static const char *GetSerializationSubclassOptionsKey() { return "Options"; }

  enum FilterTy {
    Unconstrained = 0,
    Exception,
    ByModule,
    ByModules,
    ByModulesAndCU,
    LastKnownFilterType = ByModulesAndCU,
    UnknownFilter
  };

  static const char *g_ty_to_name[LastKnownFilterType + 2];

  enum FilterTy GetFilterTy() {
    if (SubclassID > FilterTy::LastKnownFilterType)
      return FilterTy::UnknownFilter;
    else
      return (enum FilterTy)SubclassID;
  }

  const char *GetFilterName() { return FilterTyToName(GetFilterTy()); }

  static const char *FilterTyToName(enum FilterTy);

  static FilterTy NameToFilterTy(llvm::StringRef name);

protected:
  // Serialization of SearchFilter options:
  enum OptionNames { ModList = 0, CUList, LanguageName, LastOptionName };
  static const char *g_option_names[LastOptionName];

  static const char *GetKey(enum OptionNames enum_value) {
    return g_option_names[enum_value];
  }

  StructuredData::DictionarySP
  WrapOptionsDict(StructuredData::DictionarySP options_dict_sp);

  void SerializeFileSpecList(StructuredData::DictionarySP &options_dict_sp,
                             OptionNames name, FileSpecList &file_list);

  // These are utility functions to assist with the search iteration.  They are
  // used by the
  // default Search method.

  Searcher::CallbackReturn DoModuleIteration(const SymbolContext &context,
                                             Searcher &searcher);

  Searcher::CallbackReturn DoModuleIteration(const lldb::ModuleSP &module_sp,
                                             Searcher &searcher);

  Searcher::CallbackReturn DoCUIteration(const lldb::ModuleSP &module_sp,
                                         const SymbolContext &context,
                                         Searcher &searcher);

  Searcher::CallbackReturn DoFunctionIteration(Function *function,
                                               const SymbolContext &context,
                                               Searcher &searcher);

  virtual lldb::SearchFilterSP DoCopyForBreakpoint(Breakpoint &breakpoint) = 0;

  void SetTarget(lldb::TargetSP &target_sp) { m_target_sp = target_sp; }

  lldb::TargetSP
      m_target_sp; // Every filter has to be associated with a target for
                   // now since you need a starting place for the search.
private:
  unsigned char SubclassID;
};

//----------------------------------------------------------------------
/// @class SearchFilterForUnconstrainedSearches SearchFilter.h
/// "lldb/Core/SearchFilter.h"
/// @brief This is a SearchFilter that searches through all modules.  It also
/// consults the Target::ModuleIsExcludedForUnconstrainedSearches.
//----------------------------------------------------------------------
class SearchFilterForUnconstrainedSearches : public SearchFilter {
public:
  SearchFilterForUnconstrainedSearches(const lldb::TargetSP &target_sp)
      : SearchFilter(target_sp, FilterTy::Unconstrained) {}

  ~SearchFilterForUnconstrainedSearches() override = default;

  bool ModulePasses(const FileSpec &module_spec) override;

  bool ModulePasses(const lldb::ModuleSP &module_sp) override;

  static lldb::SearchFilterSP
  CreateFromStructuredData(Target &target,
                           const StructuredData::Dictionary &data_dict,
                           Status &error);

  StructuredData::ObjectSP SerializeToStructuredData() override;

protected:
  lldb::SearchFilterSP DoCopyForBreakpoint(Breakpoint &breakpoint) override;
};

//----------------------------------------------------------------------
/// @class SearchFilterByModule SearchFilter.h "lldb/Core/SearchFilter.h"
/// @brief This is a SearchFilter that restricts the search to a given module.
//----------------------------------------------------------------------

class SearchFilterByModule : public SearchFilter {
public:
  //------------------------------------------------------------------
  /// The basic constructor takes a Target, which gives the space to search,
  /// and the module to restrict the search to.
  ///
  /// @param[in] target
  ///    The Target that provides the module list to search.
  ///
  /// @param[in] module
  ///    The Module that limits the search.
  //------------------------------------------------------------------
  SearchFilterByModule(const lldb::TargetSP &targetSP, const FileSpec &module);

  SearchFilterByModule(const SearchFilterByModule &rhs);

  ~SearchFilterByModule() override;

  SearchFilterByModule &operator=(const SearchFilterByModule &rhs);

  bool ModulePasses(const lldb::ModuleSP &module_sp) override;

  bool ModulePasses(const FileSpec &spec) override;

  bool AddressPasses(Address &address) override;

  bool CompUnitPasses(FileSpec &fileSpec) override;

  bool CompUnitPasses(CompileUnit &compUnit) override;

  void GetDescription(Stream *s) override;

  uint32_t GetFilterRequiredItems() override;

  void Dump(Stream *s) const override;

  void Search(Searcher &searcher) override;

  static lldb::SearchFilterSP
  CreateFromStructuredData(Target &target,
                           const StructuredData::Dictionary &data_dict,
                           Status &error);

  StructuredData::ObjectSP SerializeToStructuredData() override;

protected:
  lldb::SearchFilterSP DoCopyForBreakpoint(Breakpoint &breakpoint) override;

private:
  FileSpec m_module_spec;
};

class SearchFilterByModuleList : public SearchFilter {
public:
  //------------------------------------------------------------------
  /// The basic constructor takes a Target, which gives the space to search,
  /// and the module list to restrict the search to.
  ///
  /// @param[in] target
  ///    The Target that provides the module list to search.
  ///
  /// @param[in] module
  ///    The Module that limits the search.
  //------------------------------------------------------------------
  SearchFilterByModuleList(const lldb::TargetSP &targetSP,
                           const FileSpecList &module_list);

  SearchFilterByModuleList(const lldb::TargetSP &targetSP,
                           const FileSpecList &module_list,
                           enum FilterTy filter_ty);

  SearchFilterByModuleList(const SearchFilterByModuleList &rhs);

  ~SearchFilterByModuleList() override;

  SearchFilterByModuleList &operator=(const SearchFilterByModuleList &rhs);

  bool ModulePasses(const lldb::ModuleSP &module_sp) override;

  bool ModulePasses(const FileSpec &spec) override;

  bool AddressPasses(Address &address) override;

  bool CompUnitPasses(FileSpec &fileSpec) override;

  bool CompUnitPasses(CompileUnit &compUnit) override;

  void GetDescription(Stream *s) override;

  uint32_t GetFilterRequiredItems() override;

  void Dump(Stream *s) const override;

  void Search(Searcher &searcher) override;

  static lldb::SearchFilterSP
  CreateFromStructuredData(Target &target,
                           const StructuredData::Dictionary &data_dict,
                           Status &error);

  StructuredData::ObjectSP SerializeToStructuredData() override;

  void SerializeUnwrapped(StructuredData::DictionarySP &options_dict_sp);

protected:
  lldb::SearchFilterSP DoCopyForBreakpoint(Breakpoint &breakpoint) override;

protected:
  FileSpecList m_module_spec_list;
};

class SearchFilterByModuleListAndCU : public SearchFilterByModuleList {
public:
  //------------------------------------------------------------------
  /// The basic constructor takes a Target, which gives the space to search,
  /// and the module list to restrict the search to.
  ///
  /// @param[in] target
  ///    The Target that provides the module list to search.
  ///
  /// @param[in] module
  ///    The Module that limits the search.
  //------------------------------------------------------------------
  SearchFilterByModuleListAndCU(const lldb::TargetSP &targetSP,
                                const FileSpecList &module_list,
                                const FileSpecList &cu_list);

  SearchFilterByModuleListAndCU(const SearchFilterByModuleListAndCU &rhs);

  ~SearchFilterByModuleListAndCU() override;

  SearchFilterByModuleListAndCU &
  operator=(const SearchFilterByModuleListAndCU &rhs);

  bool AddressPasses(Address &address) override;

  bool CompUnitPasses(FileSpec &fileSpec) override;

  bool CompUnitPasses(CompileUnit &compUnit) override;

  void GetDescription(Stream *s) override;

  uint32_t GetFilterRequiredItems() override;

  void Dump(Stream *s) const override;

  void Search(Searcher &searcher) override;

  static lldb::SearchFilterSP
  CreateFromStructuredData(Target &target,
                           const StructuredData::Dictionary &data_dict,
                           Status &error);

  StructuredData::ObjectSP SerializeToStructuredData() override;

protected:
  lldb::SearchFilterSP DoCopyForBreakpoint(Breakpoint &breakpoint) override;

private:
  FileSpecList m_cu_spec_list;
};

} // namespace lldb_private

#endif // liblldb_SearchFilter_h_
